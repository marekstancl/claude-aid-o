#!/usr/bin/env bash
# =============================================================================
# aid-finding-merge.sh — Merge AID semantic_review findings by fingerprint
#
# Usage (subcommand):
#   aid-finding-merge.sh merge_findings <file1.json> [<file2.json> ...]
#
# Sourceable: source this file and call merge_findings() directly.
#
# Input:  One or more AID protocol v2 artifact JSON files with
#         artifact_type="semantic_review" containing .semantic_review.findings[]
#
# Output (stdout): JSON object:
#   {
#     "findings": [...merged findings array sorted by fingerprint...],
#     "merge_meta": {
#       "merged_from": ["<file1>", "<file2>", ...],
#       "conflicts": [
#         {
#           "fingerprint": "sha256:...",
#           "severity_conflict": {"from": "<lower>", "to": "<higher>"},
#           "detail_union": ["<detail1>", "<detail2>"]
#         }
#       ]
#     }
#   }
#
# Callers that want only the findings array: pipe to  | jq '.findings'
#
# Algorithm:
#   1. Extract .semantic_review.findings[] from each file (missing = empty array)
#   2. Group by fingerprint
#   3. For same fingerprint: severity=max, detail=union (sorted, unique)
#   4. Record severity conflicts in merge_meta.conflicts
#   5. Sort output deterministically by fingerprint
#
# Severity order: critical(5) > high(4) > medium(3) > low(2) > info(1)
#
# Fingerprint note: each finding carries check_id + target_path + finding_class,
# so the fingerprint is recomputable via:
#   aid-finding-fingerprint.sh fingerprint <project_id> semantic_review \
#     <check_id> <target_path> <finding_class>
# (project_id is NOT stored in the finding itself — it lives in the envelope)
#
# Lossless guarantee:
#   - Count of unique fingerprints in output == union of fingerprints across all inputs
#   - No detail string is dropped (union across sources)
#   - Severity is never downgraded (only upgraded to max)
#
# Dependencies: bash 4.0+, jq
# =============================================================================

# ---------------------------------------------------------------------------
# _merge_check_deps — verify jq is available
# ---------------------------------------------------------------------------
_merge_check_deps() {
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not found on PATH." >&2
    return 1
  fi
  if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "ERROR: bash 4.0+ is required (found ${BASH_VERSION})." >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# merge_findings <file1> [<file2> ...]
#
# Main entry point. Reads .semantic_review.findings[] from each envelope file,
# merges by fingerprint (severity=max, detail=union), and emits the result
# JSON object to stdout.
#
# Exit codes:
#   0 — success
#   1 — missing file, jq/bash unavailable, or other fatal error
# ---------------------------------------------------------------------------
merge_findings() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: merge_findings <file1.json> [<file2.json> ...]" >&2
    return 1
  fi

  _merge_check_deps || return 1

  # Validate all files exist before starting work
  local f
  for f in "$@"; do
    if [[ ! -f "$f" ]]; then
      echo "ERROR: File not found: $f" >&2
      return 1
    fi
  done

  # Build a JSON array of all inputs: [{"file":"<path>","findings":[...]}]
  # Files with no .semantic_review.findings get an empty array (not an error).
  local inputs_json="[]"
  for f in "$@"; do
    local findings_from_file
    findings_from_file=$(jq -e '.semantic_review.findings // []' "$f" 2>/dev/null) || findings_from_file="[]"
    inputs_json=$(
      printf '%s' "$inputs_json" | jq \
        --arg file "$f" \
        --argjson findings "$findings_from_file" \
        '. + [{"file": $file, "findings": $findings}]'
    )
  done

  # All merge logic in a single jq program for correctness and speed.
  #
  # The program:
  #   1. Flatten all findings into one array, annotating each with source file
  #   2. Group by fingerprint
  #   3. For each group:
  #      - severity = max rank among group members
  #      - detail   = sorted unique union of all detail strings
  #      - other fields from first occurrence (by input order)
  #      - record conflict when severity differs
  #   4. Sort output by fingerprint (determinism)
  #   5. Build merge_meta wrapper
  local result
  result=$(printf '%s' "$inputs_json" | jq '
    # Severity rank: higher = more severe
    def sev_rank:
      if . == "critical" then 5
      elif . == "high"     then 4
      elif . == "medium"   then 3
      elif . == "low"      then 2
      elif . == "info"     then 1
      else 0
      end;

    # Rank to severity label
    def rank_to_sev:
      if . == 5 then "critical"
      elif . == 4 then "high"
      elif . == 3 then "medium"
      elif . == 2 then "low"
      elif . == 1 then "info"
      else "unknown"
      end;

    # Step 1: flatten all findings with their source file path
    [
      .[] |
      .file as $src |
      .findings[] |
      . + {"_src": $src}
    ] as $all_findings |

    # Merged_from: sorted list of input files (sorted for determinism)
    ([.[].file] | sort) as $merged_from |

    # Step 2: group by fingerprint, sorted for determinism
    (
      $all_findings
      | group_by(.fingerprint)
      | sort_by(.[0].fingerprint)
    ) as $groups |

    # Step 3: merge each group
    [
      $groups[] |
      . as $group |
      # first occurrence (by input order) provides base fields
      $group[0] as $first |

      # severity max
      ([$group[].severity | sev_rank] | max) as $max_rank |
      ($max_rank | rank_to_sev) as $max_sev |

      # severity min (for conflict detection)
      ([$group[].severity | sev_rank] | min) as $min_rank |
      ($min_rank | rank_to_sev) as $min_sev |

      # detail union: collect all detail strings, deduplicate, sort
      (
        [$group[] | select(.detail != null) | .detail]
        | unique
        | sort
      ) as $detail_union |

      # joined detail
      ($detail_union | join("\n---\n")) as $detail_joined |

      # Build merged finding (without internal _src annotation)
      {
        "fingerprint": $first.fingerprint,
        "severity": $max_sev,
        "lens": $first.lens,
        "check_id": $first.check_id,
        "target_path": $first.target_path,
        "finding_class": $first.finding_class,
        "status": $first.status,
        "detail": $detail_joined
      } |
      # carry optional fields from first occurrence if present
      if $first | has("occurrence_id") then . + {"occurrence_id": $first.occurrence_id} else . end
    ] as $merged_findings |

    # Step 4: build conflicts list
    [
      $groups[] |
      . as $group |
      ([$group[].severity | sev_rank] | min) as $min_rank |
      ([$group[].severity | sev_rank] | max) as $max_rank |
      select($min_rank != $max_rank) |
      {
        "fingerprint": $group[0].fingerprint,
        "severity_conflict": {
          "from": ($min_rank | rank_to_sev),
          "to": ($max_rank | rank_to_sev)
        },
        "detail_union": (
          [$group[] | select(.detail != null) | .detail]
          | unique
          | sort
        )
      }
    ] as $conflicts |

    # Step 5: output wrapper
    {
      "findings": $merged_findings,
      "merge_meta": {
        "merged_from": $merged_from,
        "conflicts": $conflicts
      }
    }
  ')

  if [[ $? -ne 0 ]]; then
    echo "ERROR: jq merge pipeline failed." >&2
    return 1
  fi

  printf '%s\n' "$result"
}

# ---------------------------------------------------------------------------
# Subcommand dispatch — allows direct execution
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    merge_findings) shift; merge_findings "$@" ;;
    *)
      echo "Usage: $(basename "$0") merge_findings <file1.json> [<file2.json> ...]" >&2
      exit 1
      ;;
  esac
fi
