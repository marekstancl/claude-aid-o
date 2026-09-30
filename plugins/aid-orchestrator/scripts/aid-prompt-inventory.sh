#!/usr/bin/env bash
# =============================================================================
# aid-prompt-inventory.sh — what each reviewer receives, and which part of it
# its findings cite (P107 Step 6)
#
#   aid-prompt-inventory.sh <evidence root>... [--json <out>] [--md <out>]
#
# Walks every review round under the evidence roots (cp1, cp2, cp3), splits
# each `prompt-<role>.md` by its `## ` headings into sections and counts lines
# per section, then reads the round's merged.json and maps every citation of
# every finding to the section it came from:
#   plan.md:N            → the plan.md section
#   critic-response.md:N → the critic-response.md section
#   diff.patch…          → diff.patch
#   files.json           → Declared scope
#   a repository path    → diff.patch when the round's packet/diff.patch touches
#                          that file (cp2/cp3), else "repository (outside the prompt)"
#                          — a cp1 reviewer has no diff, so always the latter
#   absent:path, other   → other
# The citation grammar is the adjudicator's (aid_plan_review_citation_parts),
# so the two cannot drift. lines_total comes from round.json prompt_lines when
# the round recorded it, else from the file.
#
# WHY: the packet builders decide what a reviewer receives and nothing measured
# it; the light reviewer read about 25 % of its prompt in P102/P103. This script
# only MEASURES — what to cut is the PM's decision over the report (IMP-679).
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-plan-review-packet.sh
source "${SCRIPT_DIR}/lib/aid-plan-review-packet.sh"

usage() { sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit "${1:-1}"; }

roots=(); out_json=""; out_md=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) out_json="$2"; shift 2 ;;
    --md) out_md="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    -*) echo "unknown option: $1" >&2; usage 1 ;;
    *) roots+=("$1"); shift ;;
  esac
done
[[ ${#roots[@]} -gt 0 ]] || usage 1

# _section_of <citation> <checkpoint> <round dir> — the packet section a citation points into
_section_of() {
  local c="$1" cp="$2" rd="$3" path
  case "$c" in
    plan.md:*) echo "plan.md"; return ;;
    critic-response.md:*) echo "critic-response.md"; return ;;
    diff.patch*) echo "diff.patch"; return ;;
    files.json*) echo "Declared scope"; return ;;
    absent:*) echo "other"; return ;;
  esac
  path="${c%:*}"
  [[ "$path" =~ ^[0-9a-f]{7,40}:(.+)$ ]] && path="${BASH_REMATCH[1]}"
  if [[ "$cp" != "cp1" && -f "$rd/packet/diff.patch" ]] && grep -qF -- "$path" "$rd/packet/diff.patch"; then
    echo "diff.patch"; return
  fi
  if [[ "$path" == */* || "$path" == *.* ]]; then echo "repository (outside the prompt)"; else echo "other"; fi
}

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
skipped=0; empty_roots=()

for root in "${roots[@]}"; do
  root="${root%/}"
  [[ -d "$root" ]] || { echo "skipped: no such directory ${root}" >&2; skipped=$((skipped+1)); continue; }
  project="$(basename "$(cd "$root/../../.." 2>/dev/null && pwd || echo "$root")")"
  if ! find "$root" \( -path '*/cp1/round-*/prompt-*.md' -o -path '*/cp2/step-*/round-*/prompt-*.md' -o -path '*/cp3/round-*/prompt-*.md' \) -print -quit 2>/dev/null | grep -q .; then
    empty_roots+=("${project} (${root})"); continue
  fi
  while IFS= read -r prompt; do
    [[ -n "$prompt" ]] || continue
    rd="$(dirname "$prompt")"; role="$(basename "$prompt" .md)"; role="${role#prompt-}"
    case "$rd" in
      */cp1/round-*) cp=cp1; step="" ;;
      */cp2/step-*/round-*) cp=cp2; step="$(basename "$(dirname "$rd")")" ;;
      */cp3/round-*) cp=cp3; step="" ;;
      *) continue ;;
    esac
    round="$(basename "$rd")"
    # sections: heading text without its parenthetical or colon tail; lines per section
    sections="$(awk '
      /^## / { cand=$0; sub(/^## /,"",cand); sub(/ \(.*/,"",cand); sub(/:.*/,"",cand); if (cand=="") cand="(unnamed)";
               # the plan and the diff are appended whole and may carry their own ## headings
               # (older rounds appended the plan unnumbered; a diff of markdown does too):
               # once inside them, only the critic-response section that follows the plan switches
               if (sticky && cand != "critic-response.md") { lines[sec]++; next }
               sec=cand; sticky=(sec=="plan.md" || sec=="diff.patch"); next }
      { if (sec=="") sec="(before the first heading)"; lines[sec]++ }
      END { for (s in lines) printf "%s\t%d\n", s, lines[s] }' "$prompt" | jq -R -s 'split("\n") | map(select(length>0) | split("\t") | {key: .[0], value: (.[1]|tonumber)}) | from_entries')"
    total="$(jq -r --arg r "$role" '.prompt_lines[$r] // empty' "$rd/round.json" 2>/dev/null || true)"
    [[ -n "$total" ]] || total="$(wc -l < "$prompt")"
    findings=0; cites="{}"
    if [[ -f "$rd/merged.json" ]] && ! jq -e . "$rd/merged.json" >/dev/null 2>&1; then
      echo "skipped, malformed merged.json: ${rd}" >&2; skipped=$((skipped+1)); continue
    fi
    if [[ -f "$rd/merged.json" ]]; then
      # findings this role reported (reported_by), each citation mapped to a section
      while IFS=$'\t' read -r ev; do
        [[ -n "$ev" ]] || { findings=$((findings+1)); continue; }
        findings=$((findings+1))
        while IFS= read -r part; do
          [[ -n "$part" ]] || continue
          sec="$(_section_of "$part" "$cp" "$rd")"
          cites="$(jq -c --arg s "$sec" '.[$s] = ((.[$s] // 0) + 1)' <<< "$cites")"
        done < <(aid_plan_review_citation_parts "$ev" 2>/dev/null)
      done < <(jq -r --arg r "$role" '.findings[]? | select((.reported_by // []) | index($r)) | (.evidence // "") | gsub("\t"; " ")' "$rd/merged.json" 2>/dev/null)
    else
      echo "no merged.json: ${rd}" >&2
    fi
    jq -nc --arg p "$project" --arg cp "$cp" --arg role "$role" --arg round "$round" --arg step "$step" \
           --argjson total "$total" --argjson secs "$sections" --argjson f "$findings" --argjson c "$cites" \
      '{project:$p, checkpoint:$cp, role:$role, round:$round, step:$step, lines_total:$total, lines_by_section:$secs, findings:$f, citations_by_section:$c}' >> "$tmp"
  done < <(find "$root" \( -path '*/cp1/round-*/prompt-*.md' -o -path '*/cp2/step-*/round-*/prompt-*.md' -o -path '*/cp3/round-*/prompt-*.md' \) 2>/dev/null | sort)
done

[[ -s "$tmp" ]] || { echo "no review prompts found under: ${roots[*]} (rounds skipped: ${skipped})" >&2; exit 1; }

# Aggregate per project × checkpoint × role.
agg="$(jq -s '
  def median: sort | if length == 0 then 0 elif length % 2 == 1 then .[length/2|floor] else (.[length/2-1] + .[length/2]) / 2 end;
  group_by(.project, .checkpoint, .role) | map({
    project: .[0].project, checkpoint: .[0].checkpoint, role: .[0].role,
    prompts: length,
    lines_total_median: (map(.lines_total) | median),
    lines_by_section: (map(.lines_by_section | to_entries) | add | group_by(.key) | map({key: .[0].key, value: ((map(.value) | add) / length | round)}) | from_entries),
    findings: (map(.findings) | add),
    citations_by_section: (map(.citations_by_section | to_entries) | add // [] | group_by(.key) | map({key: .[0].key, value: (map(.value) | add)}) | from_entries)
  }) | map(. + {never_cited: ([.lines_by_section | keys[]] - [.citations_by_section | keys[]])})
' "$tmp")"
# The global list comes from the totals over every row — a section one role cited is
# cited, whatever the other roles did — not from the union of the per-role lists.
global_never="$(jq -r '([.[] | .lines_by_section | keys[]] | unique) - ([.[] | .citations_by_section | keys[]] | unique) | .[]' <<< "$agg")"

md="$( {
  echo "# Prompt inventory — what each reviewer receives and which part its findings cite"
  echo
  printf 'Generated %s by `aid-prompt-inventory.sh %s`. ' "$(date -u +%Y-%m-%d)" "${roots[*]}"
  printf '%s\n' 'Lines per section are the mean over the role'"'"'s prompts (median total). `repository (outside the prompt)` counts citations of files the reviewer opened itself; `never cited` lists sections no finding of the role ever cited. Rounds before 2.98.0 appended the plan without a `## plan.md` heading, so their plan sections appear under their own names (Goal, Scope, Step N …) and their `plan.md:N` citations count towards `plan.md`. This report measures; it recommends nothing.'
  for cp in cp1 cp2 cp3; do
    rows="$(jq -r --arg cp "$cp" '.[] | select(.checkpoint == $cp)' <<< "$agg")"
    [[ -n "$rows" ]] || continue
    echo; echo "## ${cp}"; echo
    echo "| project | role | prompts | lines (median) | lines by section | findings | citations by section | never cited |"
    echo "|---|---|---|---|---|---|---|---|"
    jq -r --arg cp "$cp" '.[] | select(.checkpoint == $cp)
      | "| \(.project) | \(.role) | \(.prompts) | \(.lines_total_median) | \(.lines_by_section | to_entries | map("\(.key) \(.value)") | join(", ")) | \(.findings) | \(.citations_by_section | to_entries | map("\(.key) \(.value)") | join(", ")) | \(.never_cited | join(", ")) |"' <<< "$agg"
  done
  echo
  echo "## Sections no finding cited in any project"
  echo
  if [[ -n "$global_never" ]]; then printf '%s\n' "$global_never" | sed 's/^/- /'; else echo "(every section was cited by at least one finding)"; fi
  if (( ${#empty_roots[@]} > 0 )); then
    echo; echo "## Roots with no review prompts (no data, not zero findings)"; echo
    printf -- '- %s\n' "${empty_roots[@]}"
    echo; echo "Their evidence predates the review rounds of 2.98.0 (no prompt files exist), so the tables above cover only the projects listed in them."
  fi
  if (( skipped > 0 )); then echo; echo "Skipped roots: ${skipped}"; fi
} )"

if [[ -n "$out_json" ]]; then printf '%s\n' "$agg" > "$out_json"; fi
if [[ -n "$out_md" ]]; then printf '%s\n' "$md" > "$out_md"; else printf '%s\n' "$md"; fi
