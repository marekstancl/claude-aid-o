#!/usr/bin/env bash
# aid-test-audit-dispatch.sh — P066 Step 11.
#
# Produces the bounded, non-overlapping Wave 1-3 dispatch manifest — domain
# shards (Wave 1), cross-cutting specialists (Wave 2, measure/full only),
# and adversarial review (Wave 3). Consumes Step 5's audit config
# (max_read_only_audit_agents, allowed_runners) from the start, never a
# forward reference.
#
# Controller integration point (stated explicitly, per a real C0 review that
# found none was specified): this script does NOT itself call Agent() — it
# produces the per-shard/per-specialist manifest (focus, shard membership,
# ALREADY-RENDERED prompt path, artifact path) that the CONTROLLER then
# dispatches directly via its own Agent() calls, at most `max_concurrent_
# agents` entries live at once PER `batch` WITHIN a wave (never across
# waves — waves are sequential), writing each result to the exact
# wave-artifact path. These dispatches are explicitly NOT routed through
# aid-emit-dispatch.sh — that script's dispatch-lifecycle ledger is scoped
# to EPIC-step Agent() calls (pipeline.md §4) and its --focus allowlist does
# not (and should not) include this command's six audit focuses, since
# /aid-audit-tests is never part of the EPIC lifecycle. This audit's own
# audit-state.json is the complete dispatch-progress record.
#
# Usage:
#   aid-test-audit-dispatch.sh --catalog <path> --output-dir <dir> \
#     --mode static|measure|full [--max-agents N] [--project-root <path>] \
#     [--audit-id <id>]
#
# Output: {max_concurrent_agents, entries: [{wave, focus, shard_id,
#   run_unit_ids, batch, template, rendered_prompt_path, artifact_path,
#   producer_agent_dispatch_id}, ...]} — both printed to stdout and written
# to <output_dir>/dispatch-manifest.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-audit-config.sh
source "${SCRIPT_DIR}/lib/aid-test-audit-config.sh"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"

PROMPTS_DIR="$(cd "${SCRIPT_DIR}/../defaults/prompts" && pwd)"
SCHEMAS_DIR="$(cd "${SCRIPT_DIR}/../defaults/schemas" && pwd)"
RENDER_PROMPT="${SCRIPT_DIR}/lib/aid-render-prompt.sh"
WAVE_ARTIFACT_SCHEMA="${SCHEMAS_DIR}/test-audit-wave-artifact.schema.json"

_die() { echo "aid-test-audit-dispatch.sh: $2" >&2; exit "$1"; }

# _tad_check_shard_overlap <shards_json>
#   <shards_json>: [{"shard_id":"...", "run_unit_ids":["...", ...]}, ...]
#   Echoes any run_unit_id assigned to more than one shard (empty = no
#   overlap). Shared collision-detection primitive — a preflight check, not
#   merely an assumption the partition algorithm never fails.
_tad_check_shard_overlap() {
  local shards_json="$1"
  jq -r '[.[].run_unit_ids[]] | group_by(.) | map(select(length > 1) | .[0]) | .[]' <<<"$shards_json"
}

# _tad_render <template> <vars_json_file> <out_path>
#   Thin wrapper around the real, existing aid-render-prompt.sh — never a
#   reimplemented substitution. Dies (named error) on any render failure so
#   a manifest is never published pointing at an entry whose prompt could
#   not actually be rendered.
_tad_render() {
  local template="$1" vars_file="$2" out_path="$3"
  mkdir -p "$(dirname "$out_path")"
  bash "$RENDER_PROMPT" --template "$template" --vars-json "$vars_file" --output "$out_path" >/dev/null \
    || _die 1 "failed to render prompt for template '$template'"
}

catalog=""
output_dir=""
mode=""
max_agents=""
project_root="$(pwd)"
audit_id="audit"

# Every value-taking option checks `$# -ge 2` before consuming an operand —
# under `set -u`, reading `$2` past the end of argv is an unbound-variable
# error that crashes the script with no diagnostic (PM-confirmed blocker:
# `--catalog` as the last/only argument), not the controlled exit-2 failure
# this script's own contract requires. Matches aid-audit-tests-cli-parse.sh
# (Step 8)'s established idiom.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog) [[ $# -ge 2 ]] || _die 2 "--catalog requires a value"; catalog="$2"; shift 2 ;;
    --output-dir) [[ $# -ge 2 ]] || _die 2 "--output-dir requires a value"; output_dir="$2"; shift 2 ;;
    --mode) [[ $# -ge 2 ]] || _die 2 "--mode requires a value"; mode="$2"; shift 2 ;;
    --max-agents) [[ $# -ge 2 ]] || _die 2 "--max-agents requires a value"; max_agents="$2"; shift 2 ;;
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --audit-id) [[ $# -ge 2 ]] || _die 2 "--audit-id requires a value"; audit_id="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$catalog" && -f "$catalog" ]] || _die 2 "--catalog is required and must exist"
[[ -n "$output_dir" ]] || _die 2 "--output-dir is required"
case "$mode" in static|measure|full) ;; *) _die 2 "--mode must be one of static|measure|full" ;; esac
# PM-confirmed blocker: `--audit-id '../escape'` previously passed straight
# through into a manifest artifact_path, letting a controller be led to
# write outside the audit root. Validated BEFORE anything else runs.
adapter_validate_audit_id "$audit_id" \
  || _die 2 "--audit-id '$audit_id' is invalid (must match ^[A-Za-z0-9_-]+\$ — no '/', '..', or whitespace)"

config_json="$(load_test_audit_config "$project_root")" || _die 1 "could not load audit config"
if [[ -z "$max_agents" ]]; then
  max_agents="$(jq -r '.max_read_only_audit_agents' <<<"$config_json")"
fi
[[ "$max_agents" =~ ^[1-9][0-9]*$ ]] || _die 2 "--max-agents must be a positive integer"
allowed_runners_json="$(jq -c '.allowed_runners' <<<"$config_json")"

case "$catalog" in
  *.json) catalog_json="$(jq -c '.' "$catalog")" ;;
  *) catalog_json="$(yq -o=json '.' "$catalog")" ;;
esac

# Filter to allowed_runners BEFORE grouping — Step 5's config contract
# governs which runner families this audit dispatches against at all
# (Codex review: an earlier version loaded allowed_runners but never used
# it, making a project's real override ineffective).
catalog_run_units_json="$(jq -c '.run_units' <<<"$catalog_json")"
run_units_json="$(jq -c --argjson allowed "$allowed_runners_json" \
  'map(select(.runner as $r | $allowed | index($r) != null))' <<<"$catalog_run_units_json")"

# Fail closed, never a false-green empty-portfolio audit: PM-confirmed
# blocker — an earlier version happily produced (and the controller would
# have dispatched) a Wave 3 adversarial-review manifest over ZERO shards
# when allowed_runners filtered out every catalog run_unit, looking exactly
# like a completed, clean audit despite analyzing nothing. Named error
# instead, citing the exact counts so a PM can immediately see whether the
# catalog or the config is wrong.
catalog_unit_count="$(jq 'length' <<<"$catalog_run_units_json")"
filtered_unit_count="$(jq 'length' <<<"$run_units_json")"
if [[ "$catalog_unit_count" -gt 0 && "$filtered_unit_count" -eq 0 ]]; then
  catalog_runners="$(jq -r '[.[].runner] | unique | join(", ")' <<<"$catalog_run_units_json")"
  allowed_runners_list="$(jq -r 'join(", ")' <<<"$allowed_runners_json")"
  _die 1 "allowed_runners filtered out the ENTIRE catalog ($catalog_unit_count run_units, runners: [$catalog_runners]) against allowed_runners: [$allowed_runners_list] — refusing to dispatch a false-green, zero-portfolio audit"
fi

# ─── Wave 1: partition run_units into <= max_agents non-overlapping shards ──
# Initial grouping: runner + top-level directory of the first source_path.
# Deterministic (sorted by group key), then merged (smallest-first,
# round-robin) down to at most max_agents groups — never assigns one
# run_unit_id to two groups (it is a partition by construction; the preflight
# check below re-verifies this rather than merely assuming the algorithm
# never has a bug).
groups_json="$(jq -c --argjson max "$max_agents" '
  (reduce .[] as $u (
    {};
    ($u.source_paths[0] // "unknown") as $sp |
    ($u.runner + ":" + ($sp | split("/") | .[0:1] | join("/"))) as $key |
    .[$key] += [$u.run_unit_id]
  )) as $grouped |
  ($grouped | to_entries | sort_by(.key)) as $entries |
  if ($entries | length) <= $max then
    $entries
  else
    # Merge smallest-first, round-robin, until group count == max.
    reduce range(0; ($entries | length) - $max) as $i (
      $entries;
      (sort_by(.value | length)) as $sorted |
      ($sorted[0].value + $sorted[1].value) as $merged |
      ($sorted[2:]) + [{key: ($sorted[0].key + "+" + $sorted[1].key), value: $merged}]
    )
  end
' <<<"$run_units_json")"

shards_json="$(jq -c '
  to_entries | map({shard_id: ("shard-" + (.key | tostring)), run_unit_ids: .value.value})
' <<<"$groups_json")"

overlap="$(_tad_check_shard_overlap "$shards_json")"
if [[ -n "$overlap" ]]; then
  echo "aid-test-audit-dispatch.sh: shard overlap detected for run_unit_id(s):" >&2
  echo "$overlap" >&2
  exit 1
fi

# ─── Build unrendered entries (wave/focus/shard/artifact-path only) ─────────
entries_json="$(jq -n \
  --argjson shards "$shards_json" \
  --arg audit_id "$audit_id" \
  --arg mode "$mode" \
  --argjson max "$max_agents" \
  '
  def batched($max):
    to_entries | map(.value + {batch: (.key / $max | floor)});
  def shard_entries:
    ($shards | map({
      wave: 1,
      focus: "shard_portfolio",
      shard_id: .shard_id,
      run_unit_ids: .run_unit_ids,
      artifact_path: (".aid-o/work/test-audits/" + $audit_id + "/agents/1-shard_portfolio-" + .shard_id + ".json")
    })) | batched($max);
  def wave2_entries:
    if $mode == "static" then []
    else
      ([
        {focus: "performance_cost"},
        {focus: "flake_isolation"}
      ] | map({
        wave: 2,
        focus: .focus,
        shard_id: null,
        run_unit_ids: null,
        artifact_path: (".aid-o/work/test-audits/" + $audit_id + "/agents/2-" + .focus + ".json")
      })) | batched($max)
    end;
  def wave3_entries:
    [{
      wave: 3,
      focus: "adversarial_review",
      shard_id: null,
      run_unit_ids: null,
      artifact_path: (".aid-o/work/test-audits/" + $audit_id + "/agents/3-adversarial_review.json"),
      batch: 0
    }];
  shard_entries + wave2_entries + wave3_entries
')"

# ─── Render each entry's prompt (real aid-render-prompt.sh, no reimpl) ──────
# Codex review: an earlier version pointed every entry at an unrendered
# template with unresolved {{...}} placeholders and gave the controller no
# way to construct the required variable values (especially Wave 3's
# prior-artifact list) — a controller following the documented integration
# point could not actually dispatch a usable prompt. Every entry now carries
# a real rendered_prompt_path produced here.
mkdir -p "$output_dir"
# Canonicalize ONCE here and use this form for every downstream path built
# from output_dir — a relative/symlinked --output-dir would otherwise make
# the later path-containment check (string prefix match) compare a relative
# rendered_prompt_path against an absolute canonical root and always fail.
output_dir="$(cd "$output_dir" && pwd -P)"
rendered_dir="${output_dir}/rendered-prompts"
mkdir -p "$rendered_dir"

wave1_and_2_artifact_paths="$(jq -r '[.[] | select(.wave == 1 or .wave == 2) | .artifact_path] | join(",")' <<<"$entries_json")"

entry_count="$(jq 'length' <<<"$entries_json")"
final_ndjson="$(mktemp)"
trap 'rm -f "$final_ndjson"' EXIT

for ((i = 0; i < entry_count; i++)); do
  entry="$(jq -c ".[$i]" <<<"$entries_json")"
  wave="$(jq -r '.wave' <<<"$entry")"
  focus="$(jq -r '.focus' <<<"$entry")"
  shard_id="$(jq -r '.shard_id // empty' <<<"$entry")"
  dispatch_id="${audit_id}-${wave}-${focus}${shard_id:+-$shard_id}"
  vars_file="$(mktemp)"
  rendered_path="${rendered_dir}/${wave}-${focus}${shard_id:+-$shard_id}.txt"

  case "$focus" in
    shard_portfolio)
      template="${PROMPTS_DIR}/test-audit-shard-auditor-prompt-v1.md"
      jq -n --arg audit_id "$audit_id" --arg wave "$wave" --arg shard_id "$shard_id" \
        --arg catalog_path "$catalog" \
        --arg shard_run_unit_ids "$(jq -r '.run_unit_ids | join(",")' <<<"$entry")" \
        --arg output_schema_path "$WAVE_ARTIFACT_SCHEMA" --arg producer_agent_dispatch_id "$dispatch_id" \
        '{audit_id:$audit_id, wave:$wave, shard_id:$shard_id, catalog_path:$catalog_path, shard_run_unit_ids:$shard_run_unit_ids, output_schema_path:$output_schema_path, producer_agent_dispatch_id:$producer_agent_dispatch_id}' \
        > "$vars_file"
      ;;
    performance_cost)
      template="${PROMPTS_DIR}/test-audit-performance-cost-prompt-v1.md"
      jq -n --arg audit_id "$audit_id" --arg wave "$wave" \
        --arg measurements_path "${output_dir%/}/measurements.jsonl" --arg catalog_path "$catalog" \
        --arg output_schema_path "$WAVE_ARTIFACT_SCHEMA" --arg producer_agent_dispatch_id "$dispatch_id" \
        '{audit_id:$audit_id, wave:$wave, measurements_path:$measurements_path, catalog_path:$catalog_path, output_schema_path:$output_schema_path, producer_agent_dispatch_id:$producer_agent_dispatch_id}' \
        > "$vars_file"
      ;;
    flake_isolation)
      template="${PROMPTS_DIR}/test-audit-flake-isolation-prompt-v1.md"
      jq -n --arg audit_id "$audit_id" --arg wave "$wave" \
        --arg measurements_path "${output_dir%/}/measurements.jsonl" \
        --arg repeat_runs_path "${output_dir%/}/repeat-runs.jsonl" --arg catalog_path "$catalog" \
        --arg output_schema_path "$WAVE_ARTIFACT_SCHEMA" --arg producer_agent_dispatch_id "$dispatch_id" \
        '{audit_id:$audit_id, wave:$wave, measurements_path:$measurements_path, repeat_runs_path:$repeat_runs_path, catalog_path:$catalog_path, output_schema_path:$output_schema_path, producer_agent_dispatch_id:$producer_agent_dispatch_id}' \
        > "$vars_file"
      ;;
    adversarial_review)
      template="${PROMPTS_DIR}/test-audit-adversarial-review-prompt-v1.md"
      jq -n --arg audit_id "$audit_id" --arg wave "$wave" --arg paths "$wave1_and_2_artifact_paths" \
        --arg output_schema_path "$WAVE_ARTIFACT_SCHEMA" --arg producer_agent_dispatch_id "$dispatch_id" \
        '{audit_id:$audit_id, wave:$wave, prior_wave_artifact_paths:$paths, output_schema_path:$output_schema_path, producer_agent_dispatch_id:$producer_agent_dispatch_id}' \
        > "$vars_file"
      ;;
    *)
      _die 1 "unknown focus '$focus' — no prompt template mapping"
      ;;
  esac

  _tad_render "$template" "$vars_file" "$rendered_path"
  rm -f "$vars_file"

  entry="$(jq -c --arg t "$template" --arg r "$rendered_path" --arg d "$dispatch_id" \
    '. + {template: $t, rendered_prompt_path: $r, producer_agent_dispatch_id: $d}' <<<"$entry")"
  printf '%s\n' "$entry" >> "$final_ndjson"
done

final_entries_json="$(jq -cs '.' "$final_ndjson")"

# ─── Path-containment verification (defense-in-depth beyond audit_id's own
# regex validation) — PM-required: canonicalize and prove every
# artifact_path and rendered_prompt_path resolves inside the audit/output
# root before the manifest is ever published, not merely trust that
# audit_id validation upstream was sufficient.
audit_root_prefix=".aid-o/work/test-audits/${audit_id}/"
bad_path="$(jq -r --arg prefix "$audit_root_prefix" --arg out_root "$output_dir" '
  .[] | select((.artifact_path | startswith($prefix) | not) or (.rendered_prompt_path | startswith($out_root + "/") | not)) | .artifact_path
' <<<"$final_entries_json" | head -1)"
if [[ -n "$bad_path" ]]; then
  _die 1 "internal error: entry path escapes the audit/output root: $bad_path"
fi

manifest_json="$(jq -n --argjson max "$max_agents" --argjson entries "$final_entries_json" --arg audit_id "$audit_id" \
  '{audit_id: $audit_id, max_concurrent_agents: $max, entries: $entries}')"

printf '%s\n' "$manifest_json" > "${output_dir%/}/dispatch-manifest.json"
printf '%s\n' "$manifest_json"
