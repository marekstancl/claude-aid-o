#!/usr/bin/env bash
# =============================================================================
# lib/aid-ui-proposal.sh — a UI proposal is built from the application, not
# imagined (P087 Steps 8 + 9)
#
#   aid_ui_proposal_viewports <project_root>
#   aid_ui_proposal_build     <project_root> <out_dir> [--screen <url>]
#                             [--fixture-data <mocks.json>] [--selector <css>]
#                             [--brief <file>]
#   aid_ui_proposal_check     <proposal.json> [project_root]
#
# WHY THIS EXISTS
#   The PM's words: what the agents hand over is unusable for judging a UI
#   change. The regression side existed (UI Change Contract + the
#   `frontend_visual_fidelity_block` guard); the CREDIBILITY of a proposal had
#   nothing. This builds the proposal's basis by code, from one of two
#   sources, and says which:
#
#   live-screen    the application's real screen, captured with the same tool
#                  the regression check uses (lib/ui-fidelity/ui-capture.mjs),
#                  on FIXTURE data — a capture without a fixture file never
#                  happens, so production data is never photographed;
#   design-system  the application's own styles and components, inventoried
#                  from the tree, when there is no screen to capture (a wholly
#                  new UI, or an app that cannot be started). The proposal is
#                  MARKED as such; it never claims to be a screenshot.
#
# RESPONSIVENESS IS A FACT OF THE PROJECT, READ ONCE
#   `ui.responsive` in project.yaml (default true — the PM builds responsive
#   apps; a deliberately desktop-only app says false). When true, the basis
#   and the check cover two viewports at least: desktop and mobile. A
#   viewport that cannot be captured stops the build naming that viewport,
#   not with a general message.
#
# WHAT IT DOES NOT DO
#   It does not draft the change and does not ask a second model: the two
#   proposals come from skills/visual-companion/SKILL.md calling
#   lib/aid-brainstorm-opponent.sh with the same brief (P088's finding — the
#   opponent gets the brief, not the first model's conclusions).
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-25
# =============================================================================
[[ -n "${_AID_UI_PROPOSAL_SH_LOADED:-}" ]] && return 0
_AID_UI_PROPOSAL_SH_LOADED=1

_AID_UP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-scoping.sh
source "${_AID_UP_LIB_DIR}/aid-scoping.sh"

# The two viewports every responsive proposal covers. More may be added by
# the caller; fewer is not a proposal for a responsive app.
_AID_UP_DESKTOP='desktop 1280 720'
_AID_UP_MOBILE='mobile 390 844'

# The capture command. Overridable so the suite can prove the viewport matrix
# without a browser — the tool itself has its own fixtures.
_aid_up_capture_cmd() {
  if [[ -n "${AID_UI_CAPTURE_CMD:-}" ]]; then printf '%s' "$AID_UI_CAPTURE_CMD"
  else printf 'node %s/ui-capture.mjs' "$(cd "${_AID_UP_LIB_DIR}/../../lib/ui-fidelity" 2>/dev/null && pwd)"; fi
}

# ---------------------------------------------------------------------------
# aid_ui_proposal_viewports <project_root>
#   Prints "name width height" per line: desktop and mobile when the project
#   is responsive (the default), desktop alone when `ui.responsive: false`.
# ---------------------------------------------------------------------------
aid_ui_proposal_viewports() {
  local root="${1:?viewports: project root required}" responsive
  responsive="$(_aid_project_yaml "$root" '.ui.responsive' 2>/dev/null)" || responsive="true"
  printf '%s\n' "$_AID_UP_DESKTOP"
  [[ "$responsive" == "false" ]] || printf '%s\n' "$_AID_UP_MOBILE"
}

# _aid_up_design_system <project_root> — JSON inventory of what the app is
# styled with: style sources, a tailwind/theme config if any, component
# directories. Enough for a proposal to be drawn in the app's own vocabulary
# and for a reader to see what it was drawn from.
_aid_up_design_system() {
  local root="$1"
  local styles configs components
  styles="$(cd "$root" && find . -path ./node_modules -prune -o -path ./.git -prune -o \( -name '*.css' -o -name '*.scss' -o -name '*.less' \) -type f -print 2>/dev/null | sed 's|^\./||' | sort | head -40)"
  configs="$(cd "$root" && find . -maxdepth 3 -path ./node_modules -prune -o \( -name 'tailwind.config.*' -o -name 'theme.*' -o -name 'design-tokens.*' -o -name 'tokens.json' \) -type f -print 2>/dev/null | sed 's|^\./||' | sort)"
  components="$(cd "$root" && find . -path ./node_modules -prune -o -path ./.git -prune -o -type d \( -iname 'components' -o -iname 'ui' \) -print 2>/dev/null | sed 's|^\./||' | sort | head -20)"
  jq -n --arg s "$styles" --arg c "$configs" --arg k "$components" \
    '{style_sources: ($s | split("\n") | map(select(length > 0))),
      theme_configs: ($c | split("\n") | map(select(length > 0))),
      component_dirs: ($k | split("\n") | map(select(length > 0)))}'
}

# ---------------------------------------------------------------------------
# aid_ui_proposal_build <project_root> <out_dir> [options]
#   Writes <out_dir>/proposal.json and, on the live-screen basis, one
#   baseline capture per viewport under <out_dir>/<viewport>/.
#   0 built · 1 a viewport could not be captured (named) or an option is bad
#
#   --screen <url>            the real screen to start from
#   --fixture-data <file>     API mocks for the capture (REQUIRED for a
#                             capture: no fixture, no live screen — the basis
#                             falls back to design-system and says why)
#   --selector <css>          element to capture (default: body)
#   --brief <file>            the change brief, recorded with the proposal so
#                             both models are handed the same one
# ---------------------------------------------------------------------------
aid_ui_proposal_build() {
  local root="${1:?proposal: project root required}" out="${2:?proposal: output dir required}"; shift 2
  local screen="" fixture="" selector="body" brief=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --screen)       screen="${2:-}"; shift 2 ;;
      --fixture-data) fixture="${2:-}"; shift 2 ;;
      --selector)     selector="${2:-}"; shift 2 ;;
      --brief)        brief="${2:-}"; shift 2 ;;
      *) echo "proposal: unknown option $1" >&2; return 1 ;;
    esac
  done
  mkdir -p "$out" || { echo "proposal: cannot create ${out}" >&2; return 1; }

  local responsive="true"
  [[ "$(_aid_project_yaml "$root" '.ui.responsive' 2>/dev/null)" == "false" ]] && responsive="false"

  local basis="design-system" marked="" reason=""
  if [[ -n "$screen" && -n "$fixture" && -r "$fixture" ]]; then
    basis="live-screen"
  elif [[ -n "$screen" ]]; then
    reason="a screen was named but no readable fixture data was given — the application is never captured on real data, so the proposal is built from its design system instead"
  else
    reason="no screen to capture — the proposal is built from the application's own styles and components"
  fi
  [[ "$basis" == "design-system" ]] && marked="NO LIVE BASELINE — this proposal is built from the application's design system, not from a screenshot of the running application. ${reason}"

  local viewports="[]" name w h dir baseline
  while read -r name w h; do
    [[ -n "$name" ]] || continue
    baseline="null"
    if [[ "$basis" == "live-screen" ]]; then
      dir="${out}/${name}"; mkdir -p "$dir"
      if ! $(_aid_up_capture_cmd) --url "$screen" --selector "$selector" --target-id "baseline" \
             --output-dir "$dir" --api-mocks-file "$fixture" --viewport-width "$w" --viewport-height "$h" \
             >"${dir}/capture.log" 2>&1 || [[ ! -s "${dir}/baseline.png" ]]; then
        echo "proposal: the ${name} viewport (${w}x${h}) could not be captured from ${screen} — see ${dir}/capture.log. A proposal for this project needs every viewport; none was faked." >&2
        return 1
      fi
      baseline="\"${dir}/baseline.png\""
    fi
    viewports="$(jq -c --arg n "$name" --argjson w "$w" --argjson h "$h" --argjson b "$baseline" \
      '. + [{name: $n, width: $w, height: $h, baseline: $b, proposed: null}]' <<< "$viewports")"
  done < <(aid_ui_proposal_viewports "$root")

  local design="{}"
  [[ "$basis" == "design-system" ]] && design="$(_aid_up_design_system "$root")"

  jq -n --arg basis "$basis" --arg screen "$screen" --arg fixture "$fixture" --arg brief "$brief" \
        --arg marked "$marked" --argjson responsive "$responsive" --argjson vps "$viewports" --argjson ds "$design" \
        --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{basis: $basis, live_baseline: ($basis == "live-screen"), marked: (if $marked == "" then null else $marked end),
          screen: (if $screen == "" then null else $screen end), fixture_data: (if $fixture == "" then null else $fixture end),
          production_data_used: false, responsive: $responsive, viewports: $vps, design_system: $ds,
          brief: (if $brief == "" then null else $brief end), created_at: $at}' > "${out}/proposal.json" \
    || { echo "proposal: could not write ${out}/proposal.json" >&2; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# aid_ui_proposal_check <proposal.json> [project_root]
#   The step's gate on a finished proposal. The viewports OWED are read from
#   the project (`ui.responsive`, via <project_root>) — never from the
#   proposal, which could simply leave one out — and each of them must be in
#   the file with a PROPOSED rendering on disk; on the live-screen basis with
#   its baseline too. A design-system proposal must carry its NO LIVE BASELINE
#   mark, and the basis must be one of the two. Without <project_root> the
#   proposal's own `responsive` field decides (the fixture case). Exit 1 names
#   the first failure; 2 when the file cannot be read.
# ---------------------------------------------------------------------------
aid_ui_proposal_check() {
  local f="${1:?check: proposal file required}" root="${2:-}"
  jq -e 'type == "object" and (.viewports | type == "array")' "$f" >/dev/null 2>&1 \
    || { echo "check: ${f} is not a proposal" >&2; return 2; }
  # One read of the header fields, joined with US (0x1f) for the same reason
  # the viewport rows below are: a tab is IFS whitespace and an empty field
  # between two present ones would collapse.
  local basis live responsive marked
  IFS=$'\x1f' read -r basis live responsive marked < <(jq -r \
    '[.basis // "", (.live_baseline | tostring), (.responsive | tostring), .marked // ""] | join("\u001f")' "$f")
  case "$basis" in
    live-screen) ;;
    design-system)
      [[ "$marked" == "NO LIVE BASELINE"* ]] || { echo "check: a design-system proposal must be marked NO LIVE BASELINE — this one is not, so it could pass as a screenshot" >&2; return 1; } ;;
    *) echo "check: basis '${basis}' is neither live-screen nor design-system" >&2; return 1 ;;
  esac

  local owed
  if [[ -n "$root" ]]; then owed="$(aid_ui_proposal_viewports "$root")"
  elif [[ "$responsive" == "false" ]]; then owed="$_AID_UP_DESKTOP"
  else owed="$(printf '%s\n%s' "$_AID_UP_DESKTOP" "$_AID_UP_MOBILE")"; fi

  local name w h baseline proposed row
  while read -r name w h; do
    [[ -n "$name" ]] || continue
    # Joined with US (0x1f), not tabs: a tab is IFS whitespace, so an empty
    # baseline would collapse and `proposed` would be read as the baseline.
    row="$(jq -r --arg n "$name" '.viewports[] | select(.name == $n) | [.name, (.width|tostring), (.height|tostring), (.baseline // ""), (.proposed // "")] | join("\u001f")' "$f" | head -1)"
    [[ -n "$row" ]] || { echo "check: the ${name} viewport (${w}x${h}) is owed by this project and is not in the proposal at all" >&2; return 1; }
    local ow="$w" oh="$h"
    IFS=$'\x1f' read -r name w h baseline proposed <<< "$row"
    if [[ "$w" != "$ow" || "$h" != "$oh" ]]; then
      echo "check: the ${name} viewport is ${w}x${h} in the proposal but the project owes ${ow}x${oh}" >&2
      return 1
    fi
    if [[ "$basis" == "live-screen" && ( -z "$baseline" || ! -s "$baseline" ) ]]; then
      echo "check: the ${name} viewport (${w}x${h}) has no baseline capture — the proposal claims a live basis it does not have for this viewport" >&2
      return 1
    fi
    if [[ -z "$proposed" || ! -s "$proposed" ]]; then
      echo "check: the ${name} viewport (${w}x${h}) has no proposed rendering — a proposal for this project covers every viewport it owes" >&2
      return 1
    fi
  done <<< "$owed"
  return 0
}
