#!/usr/bin/env bash
# =============================================================================
# aid-source-plan-graph.sh — canonical dependency parser for runnable plans
#
# This is deliberately source-plan based: it runs before EPIC/plan.json exists.
# Consumers must not invent a second awk parser.  A dependency declaration is
# accepted only as `Depends on: <refs> [— annotation]`, where <refs> is a
# comma-separated list of `Step N`, `Steps X-Y`, `Task N`, `Tasks X-Y`, or one
# of the two no-dependency markers `none` (authoring form) and `---`
# (generated-canonical form).  It may be split over indented continuation
# lines.  Everything after the FIRST em dash is a human annotation and is
# ignored; every token on the LEFT of it must be recognised.  A declared but
# unparseable dependency is an error, never an empty graph.
# =============================================================================
[[ -n "${_AID_SOURCE_PLAN_GRAPH_LOADED:-}" ]] && return 0
_AID_SOURCE_PLAN_GRAPH_LOADED=1

# _aid_spg_error is set by aid_source_plan_graph on invalid input.
_aid_spg_error=""

# _aid_spg_dep_out receives _aid_spg_dep_numbers' result (one step number per
# line). It is a GLOBAL rather than stdout on purpose: reading the helper via
# a command substitution would run it in a subshell, and the specific
# _aid_spg_error it sets on a bad token would be discarded — which is exactly
# how "unrecognised dependency token 'banana'" used to degrade into a generic
# "malformed dependency declaration" (P073 Step 5).
_aid_spg_dep_out=""

_aid_spg_dep_numbers() {
  local raw="$1" token start end i found=0
  _aid_spg_dep_out=""
  # P073 Step 5: everything from the FIRST em dash on is a human annotation
  # ("Depends on: Step 2 — needs the force helper") and is discarded before
  # parsing; only the reference list to its left is graded, and every token
  # there must be recognised.
  raw="${raw%%—*}"
  # The two accepted no-dependency markers: `none` is the authoring form,
  # `---` the generated-canonical one. Case-insensitive; nothing else counts.
  case "$(printf '%s' "$raw" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')" in
    ---|none) return 0 ;;
  esac
  raw="$(printf '%s' "$raw" | tr '\n' ' ' | sed 's/,/\n/g')"
  while IFS= read -r token; do
    token="$(printf '%s' "$token" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$token" ]] && continue
    if [[ "$token" =~ ^[Ss]teps?[[:space:]]+([0-9]+)[[:space:]]*-[[:space:]]*([0-9]+) ]]; then
      start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"
      if (( start > end )); then _aid_spg_error="reversed dependency range Steps ${start}-${end}"; return 1; fi
      for ((i=start; i<=end; i++)); do _aid_spg_dep_out+="${i}"$'\n'; done
      found=1
    elif [[ "$token" =~ ^[Ss]tep[[:space:]]+([0-9]+) ]]; then
      _aid_spg_dep_out+="${BASH_REMATCH[1]}"$'\n'; found=1
    elif [[ "$token" =~ ^[Tt]asks?[[:space:]]+([0-9]+)[[:space:]]*-[[:space:]]*([0-9]+) ]]; then
      start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"
      if (( start > end )); then _aid_spg_error="reversed dependency range Tasks ${start}-${end}"; return 1; fi
      for ((i=start; i<=end; i++)); do _aid_spg_dep_out+="${i}"$'\n'; done
      found=1
    elif [[ "$token" =~ ^[Tt]ask[[:space:]]+([0-9]+) ]]; then
      _aid_spg_dep_out+="${BASH_REMATCH[1]}"$'\n'; found=1
    else
      # P073 Step 5: an unrecognised token is a LOUD failure. Previously such
      # a token was silently dropped, so `Depends on: Step 2, banana` and even
      # a no-dependency marker mixed with a real reference parsed as a partial
      # graph nobody had asked for.
      _aid_spg_error="unrecognised dependency token '${token}' — accepted: 'Step N', 'Steps N-M', 'Task N', 'Tasks N-M', 'none', '---' (optionally followed by ' — annotation')"
      return 1
    fi
  done <<< "$raw"
  if (( ! found )); then _aid_spg_error="dependency declaration has no canonical Step/Steps reference: ${1//$'\n'/ }"; return 1; fi
}

# aid_source_plan_graph <plan.md> [expected_epics]
# stdout: deterministic JSON graph; stderr: actionable error.  Returns nonzero
# for duplicate/missing/self/forward/cyclic dependencies or malformed grammar.
aid_source_plan_graph() {
  local plan="$1" expected_epics="${2:-}" record step phase deps line
  _aid_spg_error=""
  [[ -f "$plan" ]] || { _aid_spg_error="plan file not found: $plan"; return 1; }

  # Records are unit-separated (dependency prose may contain tabs). The awk keeps
  # the source block intact, including multi-line dependency continuations.
  local records
  records="$(awk '
    function flush() { if (step != "") print step "\034" step_phase "\034" deps "\034" line }
    function header_num(s, t) { t=s; sub(/^###?[[:space:]]+(Step|Task)[[:space:]]+/, "", t); sub(/[^0-9].*$/, "", t); return t }
    BEGIN { step=""; phase=""; step_phase=""; deps=""; in_deps=0; line=0 }
    {
      sub(/\r$/, "");
      if ($0 ~ /^\*\*EPIC[[:space:]]+[0-9]+/) { t=$0; sub(/^\*\*EPIC[[:space:]]+/, "", t); sub(/[^0-9].*$/, "", t); phase=t }
      if ($0 ~ /^###?[[:space:]]+(Step|Task)[[:space:]]+[0-9]+/) { flush(); step=header_num($0); step_phase=phase; deps=""; in_deps=0; line=NR; next }
      if (step == "") next
      if ($0 ~ /^\*\*Dependencies:\*\*/) { in_deps=1; t=$0; sub(/^\*\*Dependencies:\*\*[[:space:]]*/, "", t); if (t != "") deps=deps t " "; next }
      if (in_deps && $0 ~ /^\*\*[A-Z][^:]*:\*\*/) { in_deps=0 }
      # P073 Step 5: `- Blocks: Step 5` sits in the same block and is indented,
      # so the generic continuation branch used to fold it into the DEPENDS
      # set — inventing a forward dependency the author never declared.
      if (in_deps && $0 ~ /Blocks:/) next
      if (in_deps) { if ($0 ~ /^[[:space:]]*-[[:space:]]*Depends on:/ || $0 ~ /^[[:space:]]+/ || $0 ~ /^[[:space:]]*Depends on:/) { t=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", t); sub(/^Depends on:[[:space:]]*/, "", t); deps=deps t " " } }
    }
    END { flush() }
  ' "$plan")"
  [[ -n "$records" ]] || { _aid_spg_error="no Step/Task headers found"; return 1; }

  declare -A seen=() phase_for=() edge_seen=()
  local -a steps=() edges=() errors=()
  declare -A deps_for=()
  while IFS=$'\034' read -r step phase deps line; do
    [[ "$step" =~ ^[0-9]+$ ]] || { errors+=("line ${line}: unreadable step header"); continue; }
    if [[ -n "${seen[$step]:-}" ]]; then errors+=("line ${line}: duplicate Step ${step} (first at line ${seen[$step]})"); else seen[$step]="$line"; steps+=("$step"); phase_for[$step]="$phase"; fi
    deps_for[$step]="$deps"
  done <<< "$records"
  local dep
  for step in "${steps[@]}"; do
    deps="${deps_for[$step]:-}"
    if [[ -n "$deps" ]]; then
      local nums
      # Called directly (no command substitution) so the specific
      # _aid_spg_error survives into the message below — P073 Step 5.
      if ! _aid_spg_dep_numbers "$deps"; then errors+=("line ${seen[$step]}: ${_aid_spg_error:-malformed dependency declaration}"); continue; fi
      nums="$_aid_spg_dep_out"
      while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        if [[ "$dep" == "$step" ]]; then errors+=("line ${seen[$step]}: Step ${step} depends on itself"); continue; fi
        if (( dep > step )); then errors+=("line ${seen[$step]}: Step ${step} has forbidden forward dependency on Step ${dep}"); continue; fi
        local edge="${dep}->${step}"
        if [[ -n "${edge_seen[$edge]:-}" ]]; then errors+=("line ${seen[$step]}: duplicate dependency ${edge}"); continue; fi
        edge_seen[$edge]=1; edges+=("$edge")
      done <<< "$nums"
    fi
  done
  local step
  for step in "${steps[@]}"; do
    [[ -n "${phase_for[$step]:-}" || -z "$expected_epics" || "$expected_epics" == "1" ]] || errors+=("line ${seen[$step]}: Step ${step} is not assigned to an EPIC marker")
  done
  if [[ -n "$expected_epics" && "$expected_epics" != "1" ]]; then
    local p
    for ((p=1; p<=expected_epics; p++)); do
      local found=0; for step in "${steps[@]}"; do [[ "${phase_for[$step]:-}" == "$p" ]] && found=1; done
      (( found )) || errors+=("EPIC ${p}/${expected_epics} has no source steps")
    done
  fi
  local edge dep target
  for edge in "${edges[@]}"; do
    dep="${edge%%->*}"; target="${edge##*->}"
    [[ -n "${seen[$dep]:-}" ]] || errors+=("line ${seen[$target]}: Step ${target} depends on missing Step ${dep}")
  done
  if (( ${#errors[@]} )); then
    _aid_spg_error="$(printf '%s\n' "${errors[@]}")"
    # Callers commonly capture the JSON stdout; diagnostics must therefore go
    # to stderr instead of relying on a mutable shell variable across a
    # command-substitution boundary.
    printf '%s\n' "$_aid_spg_error" >&2
    return 1
  fi

  local ids_nl edges_nl graph
  ids_nl="$(printf 'step-%s\n' "${steps[@]}")"
  edges_nl="$(for edge in "${edges[@]}"; do printf 'step-%s->step-%s\n' "${edge%%->*}" "${edge##*->}"; done)"
  graph="$(build_plan_graph "$ids_nl" "$edges_nl")" || { _aid_spg_error="cannot build dependency graph"; return 1; }
  if [[ "$(jq '.cycles | length' <<< "$graph")" != "0" ]]; then _aid_spg_error="dependency cycle: $(jq -r '.cycles | join(", ")' <<< "$graph")"; return 1; fi
  local plan_sha phases_json
  plan_sha="sha256:$(sha256sum "$plan" | awk '{print $1}')"
  phases_json="$(for step in "${steps[@]}"; do printf '%s\t%s\n' "$step" "${phase_for[$step]:-}"; done | jq -Rn '[inputs | split("\t") | {step: (.[0]|tonumber), epic: (if .[1] == "" then null else (.[1]|tonumber) end)}]')"
  jq -n --arg schema "aid-source-plan-graph/v1" --arg plan_sha256 "$plan_sha" --argjson phases "$phases_json" --argjson graph "$graph" '{schema:$schema, plan_sha256:$plan_sha256, steps:$phases} + $graph'
}
