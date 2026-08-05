#!/usr/bin/env bash
# aid-test-catalog-apply-evidence.sh — the missing link.
#
# THE GAP THIS CLOSES
#   The audit can prove which run units are safe to run concurrently — that is
#   what the resource maps and the pilots are for, and a real audit of this
#   repository produced 77 evaluated lanes. But the result landed in
#   `decision.json` and NOTHING ever wrote it into the catalog, which is the
#   file every consumer actually reads. So a freshly proposed catalog came out
#   with every unit marked `unknown`, no matter how much evidence the audit had
#   gathered, and approving it silently traded a 27-minute concurrent test run
#   for a 55-minute serial one.
#
#   There was exactly one path from evidence to catalog and it was a one-shot
#   migration written for P071's text allowlist. Everything else was manual.
#
# WHAT IT DOES
#   1. Promotes the units of every `proposed_parallel` lane to `parallel.status:
#      safe`, binding each to the content it was verified against. The recorded
#      method is `resource_map_plus_pilot` — the schema's own name for exactly
#      this evidence, and the only value that describes how a lane is proven.
#   2. Carries forward evidence the PREVIOUS approved catalog already held, for
#      units still present whose content has not moved. Re-proving what is
#      already proven costs hours and learns nothing.
#
# WHY CARRYING FORWARD IS SAFE
#   Provenance is bound to a source hash and a resource digest. A carried entry
#   whose file has since changed fails its own binding and the resolver reports
#   it as `unknown` — automatically, with no list to maintain. Carrying the
#   record forward cannot launder a stale claim.
#
# Usage:
#   aid-test-catalog-apply-evidence.sh --catalog <proposed.yaml> \
#     --decision <decision.json> --project-root <root> \
#     [--previous <approved catalog>] [--output <path>]
#
#   --output defaults to editing --catalog in place.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CATALOG_SCHEMA="${PLUGIN_ROOT}/defaults/schemas/test-catalog.schema.json"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"
# shellcheck source=lib/aid-test-catalog-provenance.sh
source "${SCRIPT_DIR}/lib/aid-test-catalog-provenance.sh"

_die() { echo "aid-test-catalog-apply-evidence.sh: $2" >&2; exit "$1"; }

catalog="" decision="" project_root="" previous="" output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog)      [[ $# -ge 2 ]] || _die 2 "--catalog requires a value"; catalog="$2"; shift 2 ;;
    --decision)     [[ $# -ge 2 ]] || _die 2 "--decision requires a value"; decision="$2"; shift 2 ;;
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --previous)     [[ $# -ge 2 ]] || _die 2 "--previous requires a value"; previous="$2"; shift 2 ;;
    --output)       [[ $# -ge 2 ]] || _die 2 "--output requires a value"; output="$2"; shift 2 ;;
    *) _die 2 "unknown argument '$1'" ;;
  esac
done

[[ -n "$catalog" && -f "$catalog" ]] || _die 2 "--catalog is required and must exist"
[[ -n "$project_root" && -d "$project_root" ]] || _die 2 "--project-root is required and must exist"
[[ -z "$decision" || -f "$decision" ]] || _die 3 "--decision '$decision' does not exist"
output="${output:-$catalog}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat_json="$work/catalog.json"
yq -o=json '.' "$catalog" > "$cat_json" 2>/dev/null \
  || _die 1 "--catalog '$catalog' is not readable as YAML/JSON"

# Progress, because hashing every unit's dependency closure takes minutes on a
# real portfolio and a silent run is indistinguishable from a hung one.
_total_units="$(jq -r '.run_units | length' "$cat_json")"
_seen=0
_progress() {
  _seen=$(( _seen + 1 ))
  if (( _seen % 10 == 0 || _seen == _total_units )); then
    printf '  ... %s/%s jednotek zpracováno\n' "$_seen" "$_total_units" >&2
  fi
}

# ─── 1. Units the audit proved parallel-safe ────────────────────────────────
echo "aid-test-catalog-apply-evidence.sh: ${_total_units} run units to process" >&2
promoted=0
if [[ -n "$decision" ]]; then
  # `proposed_parallel` is the only lane disposition that asserts safety.
  # keep_serial, blocked_pending_fix and context_required all say the opposite
  # or say nothing, and none of them may promote anything.
  while IFS=$'\t' read -r uid evref; do
    [[ -n "$uid" ]] || continue
    h="$(aid_test_catalog_provenance_hash "$uid" "$catalog" "$project_root" 2>/dev/null || true)"
    d="$(aid_test_catalog_provenance_resource_digest "$uid" "$catalog" "$project_root" 2>/dev/null || true)"
    if [[ ! "$h" =~ ^[0-9a-f]{64}$ || ! "$d" =~ ^[0-9a-f]{64}$ ]]; then
      # A unit whose content cannot be hashed cannot be bound, and an unbound
      # `safe` is a claim rather than evidence. Left alone, loudly.
      echo "  skipped '$uid' — its content could not be hashed, so the promotion could not be bound to anything" >&2
      continue
    fi
    U="$uid" H="$h" D="$d" E="${evref:-audit-lane}" T="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      jq --arg u "$uid" --arg h "$h" --arg dg "$d" --arg e "${evref:-audit-lane}" \
         --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      .run_units |= map(
        if .run_unit_id == $u then
          .parallel.status = "safe"
          | .parallel.provenance = {evidence_ref:$e, verified_at:$t,
                                    method:"resource_map_plus_pilot",
                                    source_sha256:$h, resource_digest:$dg}
        else . end)' "$cat_json" > "$work/next.json"
    mv "$work/next.json" "$cat_json"
    promoted=$(( promoted + 1 ))
    _progress
  done < <(jq -r '
    (.parallelization.lanes // [])[]
    | select(.disposition == "proposed_parallel")
    | (.evidence_refs[0] // "audit-lane") as $e
    | .run_unit_ids[] | [., $e] | @tsv' "$decision" 2>/dev/null || true)
fi

# ─── 2. Evidence the previous approved catalog already held ─────────────────
carried=0 stale=0
if [[ -n "$previous" && -f "$previous" ]]; then
  prev_json="$work/previous.json"
  yq -o=json '.' "$previous" > "$prev_json" 2>/dev/null \
    || _die 1 "--previous '$previous' is not readable as YAML/JSON"

  while IFS=$'\t' read -r uid st evref method; do
    [[ -n "$uid" ]] || continue
    # Never overwrite what this audit just proved.
    cur="$(jq -r --arg u "$uid" '.run_units[] | select(.run_unit_id == $u) | .parallel.status // empty' "$cat_json")"
    [[ -n "$cur" ]] || continue          # unit no longer exists — nothing to carry
    [[ "$cur" == "unknown" ]] || continue

    h="$(aid_test_catalog_provenance_hash "$uid" "$catalog" "$project_root" 2>/dev/null || true)"
    d="$(aid_test_catalog_provenance_resource_digest "$uid" "$catalog" "$project_root" 2>/dev/null || true)"
    old_h="$(jq -r --arg u "$uid" '.run_units[] | select(.run_unit_id == $u) | .parallel.provenance.source_sha256 // empty' "$prev_json")"
    old_d="$(jq -r --arg u "$uid" '.run_units[] | select(.run_unit_id == $u) | .parallel.provenance.resource_digest // empty' "$prev_json")"

    # The content must be the SAME content the old verdict was about. This is
    # the whole safety of carrying anything forward.
    if [[ "$h" != "$old_h" || "$d" != "$old_d" || -z "$h" ]]; then
      stale=$(( stale + 1 ))
      _progress
      continue
    fi
    jq --arg u "$uid" --arg s "$st" --arg e "$evref" --arg m "$method" \
       --arg h "$h" --arg dg "$d" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      .run_units |= map(
        if .run_unit_id == $u then
          .parallel.status = $s
          | .parallel.provenance = {evidence_ref:$e, verified_at:$t, method:$m,
                                    source_sha256:$h, resource_digest:$dg}
        else . end)' "$cat_json" > "$work/next.json"
    mv "$work/next.json" "$cat_json"
    carried=$(( carried + 1 ))
    _progress
  done < <(jq -r '
    .run_units[]
    | select((.parallel.status // "unknown") != "unknown")
    | select(.parallel.provenance != null)
    | [.run_unit_id, .parallel.status,
       (.parallel.provenance.evidence_ref // "carried"),
       (.parallel.provenance.method // "resource_map_plus_pilot")] | @tsv' "$prev_json" 2>/dev/null || true)
fi

# ─── Publish ────────────────────────────────────────────────────────────────
adapter_validate_schema "$CATALOG_SCHEMA" "$(cat "$cat_json")" \
  || _die 1 "applying evidence produced a catalog that fails the catalog schema — refusing to write it"

tmp_out="${output}.tmp.$$"
yq -P '.' < "$cat_json" > "$tmp_out"
mv "$tmp_out" "$output"

total="$(jq -r '.run_units | length' "$cat_json")"
safe="$(jq -r '[.run_units[] | select((.parallel.status // "unknown") != "unknown")] | length' "$cat_json")"
echo "aid-test-catalog-apply-evidence.sh: ${total} run units, ${safe} carrying parallel evidence (${promoted} proved by this audit, ${carried} carried forward, ${stale} not carried because their content moved)"
