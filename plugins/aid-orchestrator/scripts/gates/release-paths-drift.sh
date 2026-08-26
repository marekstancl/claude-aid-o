#!/usr/bin/env bash
# =============================================================================
# release-paths-drift.sh — the release path lists versus what is actually
# packaged (P089 Step 10)
#
#   release-paths-drift.sh [--root <path>] [--dockerfile <path>…]
#
# WHY
#   `versioning.app_paths` / `release_exempt_paths` are a claim about what
#   reaches a user. A Dockerfile's COPY/ADD lines are a SECOND claim about the
#   same thing. When the two drift apart the release guard (Step 7) waves
#   through a change that then ships. This gate compares the two claims.
#
#   Two rules, and only what a machine can decide:
#     1. no COPY/ADD source lies ENTIRELY inside release_exempt_paths — if it
#        is packaged, changing it is not exempt;
#     2. every repository-relative source is covered by app_paths — if it is
#        packaged, it is application.
#
# WIRING, STATED PLAINLY
#   In THIS repository it is wired as `check_release_paths`, `required: false`,
#   in the `full` and `release` gate profiles only — a plan-final question,
#   asked once where it matters rather than on every step. A disagreement is
#   REPORTED and the run continues, because AID ships two products down two
#   channels (the image carries `packages/`; the plugin travels through the git
#   marketplace and never enters the image), and which of the two claims is
#   wrong is a question for a person.
#
#   In a CONSUMER project it is attached to nothing until they wire it: what
#   belongs in their image is theirs, and a detector that blocks by default in
#   every project it was never designed against is how a gate gets disabled
#   wholesale.
#
#   IT MATCHES LITERALLY. `COPY package*.json` is the source `package*.json`,
#   so `app_paths` needs that same glob — the gate never expands one against a
#   working directory that may not be the build context.
#
# EXIT
#   0  the two claims agree, or there is nothing to compare (no Dockerfile, no
#      configured lists) — the reason is printed either way
#   1  they disagree; every offending source is named
#   2  a Dockerfile exists and cannot be read — never a silent pass
#
# **Last Updated:** 2026-08-26
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/aid-release-scope.sh
source "${SCRIPT_DIR}/../lib/aid-release-scope.sh"

ROOT=""
DOCKERFILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --dockerfile) DOCKERFILES+=("${2:-}"); shift 2 ;;
    -h|--help) sed -n '3,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "release-paths-drift.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[[ -n "$ROOT" ]] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if (( ${#DOCKERFILES[@]} == 0 )); then
  while IFS= read -r f; do
    [[ -n "$f" ]] && DOCKERFILES+=("$f")
  done < <(find "$ROOT" -maxdepth 2 \( -name 'Dockerfile' -o -name 'Dockerfile.*' \) 2>/dev/null | sort)
fi

if (( ${#DOCKERFILES[@]} == 0 )); then
  echo "release-paths-drift: no Dockerfile — nothing to compare, the gate does not apply."
  exit 0
fi

EXEMPT="$(_aid_rs_cfg "$ROOT" release_exempt_paths)" || EXEMPT=""
APP="$(_aid_rs_cfg "$ROOT" app_paths)" || APP=""
if [[ -z "$EXEMPT" && -z "$APP" ]]; then
  echo "release-paths-drift: this project declares neither versioning.release_exempt_paths nor versioning.app_paths — there is no claim to compare the image against. Run '/aid-setup scan'."
  exit 0
fi

violations=0
for df in "${DOCKERFILES[@]}"; do
  if [[ ! -r "$df" ]]; then
    echo "release-paths-drift: ${df} exists but cannot be read — refusing to pass without looking." >&2
    exit 2
  fi
  # COPY/ADD sources, minus the last word (the destination) and minus any
  # `--from=` stage copy, which comes from a build stage and not the repository.
  # Continuation lines are joined first so a wrapped COPY is not half-read.
  while IFS= read -r line; do
    case "$line" in
      COPY\ *|ADD\ *|copy\ *|add\ *) ;;
      *) continue ;;
    esac
    [[ "$line" == *--from=* ]] && continue
    # Drop the instruction word and any remaining flags, then the destination.
    instr_args="${line#* }"
    # DOCKER'S JSON-ARRAY FORM. `COPY ["src", "/app/"]` is valid and would come
    # out of a shell split as `["src",` — a source that matches nothing and
    # therefore a false refusal. The brackets, quotes and commas are stripped
    # before the split rather than after.
    if [[ "$instr_args" == \[* ]]; then
      instr_args="${instr_args#[}"
      instr_args="${instr_args%]}"
      instr_args="${instr_args//,/ }"
      instr_args="${instr_args//\"/}"
    fi
    # GLOBBING OFF FOR THE SPLIT. `COPY package*.json /app/` would otherwise be
    # expanded against the CALLER'S working directory, so the gate would judge
    # a different source list from the one docker build sees.
    set -f
    # shellcheck disable=SC2086
    set -- $instr_args
    set +f
    (( $# >= 2 )) || continue
    args=("$@")
    unset 'args[${#args[@]}-1]'
    for src in "${args[@]}"; do
      [[ "$src" == --* ]] && continue
      src="${src#./}"
      src="${src%/}"
      [[ -n "$src" ]] || continue
      if [[ -n "$EXEMPT" ]] && _aid_rs_match "$src" "$EXEMPT"; then
        echo "release-paths-drift: ${df} packages '${src}', which release_exempt_paths calls exempt — a change to it would ship without a release." >&2
        violations=$((violations + 1))
        continue
      fi
      # `COPY . .` is the whole build context: it packages everything, so the
      # two claims cannot be compared source by source. It is reported as the
      # widest possible drift rather than waved through.
      if [[ "$src" == "." ]]; then
        if [[ -n "$EXEMPT" ]]; then
          echo "release-paths-drift: ${df} packages the whole build context ('COPY . .'), so every exempt path ships too." >&2
          violations=$((violations + 1))
        fi
        continue
      fi
      if [[ -n "$APP" ]] && ! _aid_rs_match "$src" "$APP"; then
        echo "release-paths-drift: ${df} packages '${src}', which app_paths does not cover — the release guard would not treat a change to it as application code." >&2
        violations=$((violations + 1))
      fi
    done
  done < <(sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' "$df" | sed 's/^[[:space:]]*//; s/[[:space:]]\+/ /g' | grep -viE '^#')
done

if (( violations > 0 )); then
  echo "release-paths-drift: ${violations} disagreement(s) between the packaged image and the declared release paths." >&2
  exit 1
fi
echo "release-paths-drift: the packaged sources agree with the declared release paths."
exit 0
