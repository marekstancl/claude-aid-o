#!/usr/bin/env bash
# =============================================================================
# aid-standards-map.sh — which ecosystem standards bind the paths a plan
# declares (P085 Step 4).
#
# This is the ONLY file in AID that reads a foreign live document: the map at
# /ecosystem/specs/standards-map, whose machine block (`schema_version: 1`,
# `tags:`, `standards[]`) is the tool-facing half of a page a human also reads.
# Into the rest of AID it exports nothing but a list of standard ids, so the
# map's format can age without touching the lint or the review contracts.
#
# The map is NEVER copied into the repository. It is live, it changes, and a
# copy would be a second map that disagrees with the first. It is read through
# a path recorded in `.aid-o/config/project.yaml → standards.map_path`, next to
# the `standards.active` key /aid-init already writes — one family of keys, two
# consumers.
#
# Sourced by aid-plan-lint.sh; also runnable as `aid-standards-map.sh --self-test`.
# =============================================================================

_AID_SM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-scoping.sh
[[ -n "${_AID_FILES_VERB_RE:-}" ]] || source "${_AID_SM_DIR}/aid-scoping.sh"

# THE PATH PATTERNS LIVE IN THE MAP, NOT HERE. This file used to carry its own
# area→tag table, which encoded THIS ecosystem's tag names and THIS repository's
# layout — so in a project with its own map nothing matched, nothing was
# derived, and `plan_standards_named` sat in the enforcement registry as
# `blocking` while being unable to fire. A check that cannot fire is the
# decoration AID-v3-principles.md §1 is about.
#
# There is deliberately NO built-in fallback. A map configured without
# `tag_paths` is a BROKEN CONFIGURATION, not a project without standards, and
# the reader says so out loud: guessing a foreign repository's layout from ours
# would replace one silent hole with a louder wrong answer.
#
# Pattern semantics are defined on the map page (§"Slovník tagů") and honoured
# here: whole declared path, `*` crosses `/` (bash pattern matching, so no `**`
# is needed), case sensitive, no negation, and ALL matching tags apply.

# aid_standards_map_file <project-root> — the configured map, or nothing.
# Return 1 = the project has no map configured (it owes no standards, and that
# is a legitimate state). Return 2 = a map IS configured but cannot be read, or
# `yq` is missing: a broken environment, which is a different answer from "no
# standards" and must never be silently rounded down to it.
aid_standards_map_file() {
  local root="$1" p rc
  p="$(_aid_project_yaml "$root" '.standards.map_path // ""')"; rc=$?
  [[ "$rc" -eq 0 ]] || return "$rc"
  [[ "$p" == /* ]] || p="${root}/${p}"
  [[ -r "$p" ]] || return 2
  printf '%s' "$p"
}

# aid_standards_block <map-file> — the map's machine block: the LAST ```yaml
# fenced block on the page. Last, because the page's prose may quote the format
# earlier, and the maintenance rule ("table and block change together") puts
# the authoritative copy at the end.
aid_standards_block() {
  awk '
    /^```yaml[[:space:]]*$/ { inside = 1; buf = ""; next }
    inside && /^```[[:space:]]*$/ { last = buf; inside = 0; next }
    inside { buf = buf $0 "\n" }
    END { printf "%s", last }
  ' "$1"
}

# aid_standards_tags_for_path <path> <patterns-file> — the tags one declared
# path belongs to. <patterns-file> holds "<tag>\t<glob>" lines, read from the
# map by aid_standards_derive.
#
# The glob is used UNQUOTED on the right of `==`, which is what makes it a
# pattern rather than a literal — and is safe: bash pattern matching only ever
# matches, it never expands a command. `*` crossing `/` is bash's own rule and
# is exactly what the map documents.
aid_standards_tags_for_path() {
  local path="${1#./}" tag glob
  while IFS=$'\t' read -r tag glob; do
    [[ -n "${glob:-}" ]] || continue
    # shellcheck disable=SC2053
    [[ "$path" == $glob ]] && printf '%s\n' "$tag"
  done < "$2"
}

# aid_standards_unknown_tags <block-file> — tags used by a standard but absent
# from the map's own tag vocabulary. A defect OF THE MAP: reported so it gets
# fixed, never a reason to stop a plan (the map is an index; a plan is not
# responsible for its bookkeeping).
aid_standards_unknown_tags() {
  # Two flat lists and `comm`, rather than one clever expression: yq dialects
  # differ on set operations, and this file has to keep working on whichever
  # one a project has installed.
  #
  # BOTH users of a tag are checked: a standard may cite one, and `tag_paths`
  # may carry patterns for one. A pattern under an unknown tag can never yield
  # a standard, so it is the same defect wearing a different hat.
  comm -23 \
    <({ yq -r '[ .standards[]?.tags[]? ] | .[]' "$1" 2>/dev/null
        yq -r '.tag_paths // {} | keys | .[]' "$1" 2>/dev/null; } | sort -u) \
    <(yq -r '(.tags // {}) | keys | .[]' "$1" 2>/dev/null | sort -u)
}

# aid_standards_derive <plan> <project-root> — the obligation, one line per
# derived tag: "<tag>\t<id>,<id>,…" (the active standards carrying that tag).
# Return 0 with lines (possibly none), 1 = no map configured, 2 = configured
# but unreadable / no yq.
#
# PER TAG, not per standard, and that is the load-bearing choice here: the map's
# tags are areas, and one area carries several standards (`dokumentace` alone
# carries four). Demanding all four of a plan that touches docs/ would be an
# obligation nobody could satisfy honestly, so what the plan owes is to name at
# least one standard from each area it reaches — which is exactly what the map
# is for ("I touched this area; here is where I looked").
# _aid_sm_block_file <project-root> — the map's machine block in a temp file,
# validated. ONE preamble for both public entry points: the earlier two copies
# had already drifted, so a broken block read as "unreadable" from one of them
# and as "no defects" from the other.
#
# Present is not the same as readable: a block that does not parse, or that
# carries no `standards:` list, would otherwise derive an EMPTY obligation, and
# "this project has no standards" is the one answer a broken map must not give.
# THE schema version this reader understands. A map that declares another one
# is refused rather than read hopefully: the block's shape is the contract, and
# a reader that guesses at version 2 is a reader that reports whatever it
# happened to find.
_AID_SM_SCHEMA=1

_aid_sm_block_file() {
  local map block_file ver
  map="$(aid_standards_map_file "$1")" || return $?
  block_file="$(mktemp)" || return 2
  aid_standards_block "$map" > "$block_file"
  if [[ ! -s "$block_file" ]] || ! yq -e '.standards | length > 0' "$block_file" >/dev/null 2>&1; then
    rm -f "$block_file"; return 2
  fi
  ver="$(yq -r '.schema_version // ""' "$block_file" 2>/dev/null)"
  if [[ "$ver" != "$_AID_SM_SCHEMA" ]]; then
    rm -f "$block_file"; return 2
  fi
  # The patterns are the half this reader cannot supply itself.
  if ! yq -e '.tag_paths | length > 0' "$block_file" >/dev/null 2>&1; then
    rm -f "$block_file"; return 2
  fi
  printf '%s' "$block_file"
}

aid_standards_derive() {
  local plan="$1" root="$2" block_file bullet body p
  block_file="$(_aid_sm_block_file "$root")" || return $?
  # The patterns, once: "<tag>\t<glob>" per line, straight from the map.
  local pat_file; pat_file="$(mktemp)"
  yq -r '.tag_paths // {} | to_entries[] | . as $e | $e.value[]? | $e.key + "\t" + .' \
    "$block_file" 2>/dev/null > "$pat_file"
  # Every declared path -> its tags, de-duplicated.
  local tags_file; tags_file="$(mktemp)"
  while IFS=$'\t' read -r _ bullet; do
    body="$(_aid_files_bullet_body "$bullet")" || continue
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      aid_standards_tags_for_path "$p" "$pat_file"
    done < <(_aid_split_path_entry "$body" 2>/dev/null || true)
  done < <(_aid_extract_files_bullets_numbered < "$plan") | sort -u > "$tags_file"
  # ONE yq over the block for every (tag, id) pair, joined against the derived
  # tags in awk. The earlier shape forked yq once per derived tag — four to six
  # process starts and as many re-parses of the same document, on a program that
  # runs at every plan write and again in generation pre-flight.
  local pairs_file; pairs_file="$(mktemp)"
  yq -r '.standards[]? | select((.status // "active") == "active")
         | . as $s | .tags[]? | . + "\t" + $s.id' "$block_file" 2>/dev/null > "$pairs_file"
  awk -F'\t' '
    NR == FNR { want[$0] = 1; next }
    # A separate `seen` counter, not `($1 in ids) ? …`: awk creates the array
    # element when it evaluates the assignment target, so the ternary saw its
    # own empty slot and every list came back with a leading comma.
    $1 in want { ids[$1] = seen[$1]++ ? ids[$1] "," $2 : $2 }
    END { for (t in ids) print t "\t" ids[t] }
  ' "$tags_file" "$pairs_file" | sort
  rm -f "$block_file" "$tags_file" "$pairs_file" "$pat_file"
  return 0
}

# aid_standards_map_defects <plan> <project-root> — unknown-tag defects of the
# configured map, for reporting. Same return codes as aid_standards_derive.
aid_standards_map_defects() {
  local block_file
  block_file="$(_aid_sm_block_file "$2")" || return $?
  aid_standards_unknown_tags "$block_file"
  rm -f "$block_file"
}

# --derive <plan>: the standards this plan's declared paths bind, one
# "<area-tag>\t<id>,<id>" per line. The CLI exists because the C0 dispatch has
# to PASTE this list into a lens prompt (commands/aid-plan.md), and a sourced
# shell function is not something a prompt can quote.
#
# --self-test: the derivation agrees with the live map for three control paths.
# Runnable, because "the tool and the map still say the same thing" is a claim
# that decays silently — the map is edited by people who do not run AID.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # The checkout this file lives in — asked for, not counted out in `..`s that
  # break silently the day the library moves a directory.
  root="$(git -C "$_AID_SM_DIR" rev-parse --show-toplevel 2>/dev/null)" \
    || root="$(cd "${_AID_SM_DIR}/../../../.." && pwd)"
  if [[ "${1:-}" == "--derive" ]]; then
    [[ -n "${2:-}" && -f "$2" ]] || { echo "Usage: aid-standards-map.sh --derive <plan.md>" >&2; exit 2; }
    # The plan's own workspace decides which map applies, not this file's repo:
    # the same resolution aid-plan-lint.sh uses, so the dispatch and the lint
    # cannot read two different maps for one plan.
    # shellcheck source=aid-plan-band.sh
    source "${_AID_SM_DIR}/aid-plan-band.sh"
    derive_root="$(_aid_band_project_root "$2")" || derive_root="$root"
    aid_standards_derive "$2" "$derive_root"; derive_rc=$?
    case "$derive_rc" in
      1) echo "aid-standards-map: no standards map configured for ${derive_root} — this project owes no '## Standards' section." >&2 ;;
      2) echo "aid-standards-map: a map IS configured for ${derive_root} but it cannot be read (missing file, unparseable machine block, or no yq)." >&2 ;;
    esac
    exit "$derive_rc"
  fi
  [[ "${1:-}" == "--self-test" ]] || { echo "Usage: aid-standards-map.sh --self-test | --derive <plan.md>" >&2; exit 2; }
  plan="$(mktemp)"; trap 'rm -f "$plan"' EXIT
  {
    printf -- '---\nid: P999\n---\n\n### Step 1: control\n\n**Files:**\n'
    printf -- '- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-control.bats`\n'
    printf -- '- Modify: `.github/workflows/nightly-tests.yml`\n'
    printf -- '- Modify: `docs/plans/control.md`\n'
  } > "$plan"
  derived="$(aid_standards_derive "$plan" "$root")"; rc=$?
  case "$rc" in
    1) echo "self-test SKIP: no standards.map_path configured for ${root}"; exit 0 ;;
    2) echo "self-test FAIL: standards.map_path is configured but the map (or yq) is unreachable" >&2; exit 1 ;;
  esac
  fail=0
  for want in "testy:test-standard" "ci-versioning:ci-versioning-standard" "dokumentace:documentation-placement"; do
    tag="${want%%:*}"; id="${want#*:}"
    line="$(printf '%s\n' "$derived" | awk -F'\t' -v t="$tag" '$1 == t {print $2}')"
    if [[ ",$line," != *",$id,"* ]]; then
      echo "self-test FAIL: path tagged '${tag}' did not derive '${id}' (got: ${line:-nothing})" >&2
      fail=1
    fi
  done
  defects="$(aid_standards_map_defects "$plan" "$root")"
  [[ -n "$defects" ]] && echo "self-test NOTE: the map uses tag(s) missing from its own vocabulary: $(echo "$defects" | tr '\n' ' ')"
  [[ "$fail" -eq 0 ]] && echo "self-test PASS: three control paths derive their standards from the live map"
  exit "$fail"
fi
