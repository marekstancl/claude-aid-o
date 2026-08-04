#!/usr/bin/env bash
# test-integration-scheduler-catalog-consumption.sh — P072 Step 25.
#
# The scheduler and the lane runner must agree about the same unit. Before
# P072 they could not: the lane resolved through provenance while the scheduler
# read `parallel.status` raw and applied its overlay on top, so a unit the lane
# had retired could still be dispatched as safe.
#
# This asserts the agreement directly — the resolver's answer and the
# scheduler's selection, over one catalog — rather than asserting each side
# against its own expectation and hoping the two expectations match.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCHED="${PLUGIN_DIR}/scripts/aid-test-scheduler.sh"

pass=0; fail=0
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }

for dep in jq yq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

# shellcheck disable=SC1090
source "${PLUGIN_DIR}/scripts/lib/aid-test-catalog-provenance.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PROJ="$WORK/project"
mkdir -p "$PROJ/.aid-o/config"
AT='@'"test"

printf '%s "a" { true; }\n' "$AT" > "$PROJ/a.bats"
printf '%s "b" { true; }\n' "$AT" > "$PROJ/b.bats"

_catalog() {   # <status-a> <status-b>
  jq -n --arg sa "$1" --arg sb "$2" '
  {schema_version:"1.0.0", generated_at:"2026-08-04T00:00:00Z", status:"approved",
   run_units:[
     {run_unit_id:"bats:a", runner:"bats", source_paths:["a.bats"], production_surfaces:["a.bats"],
      test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
      command:{type:"argv",argv:["bash","-c","echo A; exit 0"]}, runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
      parallel:{status:$sa, exclusive_resources:[], max_workers:null, internal_parallelism:false,
                provenance:{evidence_ref:"fixture", verified_at:"2026-08-02T00:00:00Z",
                            method:"resource_map_plus_pilot", source_sha256:"PH", resource_digest:"PH"}},
      isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
      recommendation:"keep", test_cases:[]},
     {run_unit_id:"bats:b", runner:"bats", source_paths:["b.bats"], production_surfaces:["b.bats"],
      test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
      command:{type:"argv",argv:["bash","-c","echo B; exit 0"]}, runtime:{fingerprint:"sha256:bbbbbbbbbbbb"},
      parallel:{status:$sb, exclusive_resources:[], max_workers:null, internal_parallelism:false,
                provenance:{evidence_ref:"fixture", verified_at:"2026-08-02T00:00:00Z",
                            method:"resource_map_plus_pilot", source_sha256:"PH", resource_digest:"PH"}},
      isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
      recommendation:"keep", test_cases:[]}],
   source_pattern_mappings: [], mapping_approval: {status:"proposed"}}' \
  | yq -P '.' > "$PROJ/.aid-o/config/test-catalog.yaml"

  # Bind each non-unknown status to real content, as a migrated or piloted
  # entry is bound. An unbound `safe` resolves to `unknown` — correctly — and
  # would make this fixture assert nothing.
  local u h d
  for u in "bats:a" "bats:b"; do
    [[ "$(yq -r ".run_units[] | select(.run_unit_id == \"$u\") | .parallel.status" "$PROJ/.aid-o/config/test-catalog.yaml")" == "unknown" ]] && continue
    h="$(aid_test_catalog_provenance_hash "$u" "$PROJ/.aid-o/config/test-catalog.yaml" "$PROJ" 2>/dev/null)"
    d="$(aid_test_catalog_provenance_resource_digest "$u" "$PROJ/.aid-o/config/test-catalog.yaml" "$PROJ" 2>/dev/null)"
    [[ "$h" =~ ^[0-9a-f]{64}$ ]] || continue
    B_ID="$u" B_H="$h" B_D="$d" yq -i '
      (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.provenance.source_sha256) = strenv(B_H)
      | (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.provenance.resource_digest) = strenv(B_D)' \
      "$PROJ/.aid-o/config/test-catalog.yaml"
  done
}

# The scheduler refuses units without `membership_verified` — as it should.
# A fixture missing it made the scheduler bail out before scheduling anything,
# which meant a later assertion ("it isolated the revoked unit too") was
# passing because NOTHING ran, not because the resolver was honoured.
_units() {
  jq -nc '[
    {unit_id:"bats:a", command:{type:"shell",shell:"echo A; exit 0"}, deadline_seconds:10,
     resource_locks:[], parallel_eligible:false, membership_verified:true, dedup:false,
     membership_binding:{catalog_fingerprint:"sha256:aaaaaaaaaaaa", verified_at:"2026-08-02T00:00:00Z", verifier_run_id:"v1"}},
    {unit_id:"bats:b", command:{type:"argv",argv:["bash","-c","echo B; exit 0"]}, deadline_seconds:10,
     resource_locks:[], parallel_eligible:false, membership_verified:true, dedup:false,
     membership_binding:{catalog_fingerprint:"sha256:bbbbbbbbbbbb", verified_at:"2026-08-02T00:00:00Z", verifier_run_id:"v1"}}
  ]' > "$PROJ/units.json"
}

_resolver_says() {   # <unit>
  aid_test_catalog_effective_status_map "$PROJ/.aid-o/config/test-catalog.yaml" "$PROJ" 2>/dev/null \
    | jq -r --arg u "$1" '.[$u] // "unknown"'
}

_scheduler_batches_together() {
  local out
  out="$(bash "$SCHED" dispatch --project-root "$PROJ" --run-id "$1" \
          --units-json "$PROJ/units.json" --mode observe_parallel --max-workers 4 2>"$WORK/sched-err.txt")" || {
    echo "    (scheduler stderr: $(head -3 "$WORK/sched-err.txt" | tr '\n' ' '))" >&2
    return 1
  }
  [[ "$(jq -r '(.units[] | select(.unit_id=="bats:a") | .co_scheduled_with) | length' <<<"$out")" -gt 0 ]]
}

echo "TEST: both safe — the resolver says safe and the scheduler batches them"
_catalog safe safe; _units
if [[ "$(_resolver_says "bats:a")" == "safe" ]]; then
  pass_msg "the resolver reports bats:a as safe"
else
  fail_msg "the resolver reports bats:a as $(_resolver_says "bats:a")"
fi
if _scheduler_batches_together c1; then
  pass_msg "the scheduler batches them — its selection matches the resolver"
else
  fail_msg "the scheduler isolated units the resolver called safe — the two disagree"
fi

echo "TEST: a source change revokes the unit in BOTH"
# The lane and the scheduler must retire the same unit for the same reason.
printf '%s "gains a lock" { flock /var/lock/consumption.lock true; }\n' "$AT" >> "$PROJ/a.bats"
if [[ "$(_resolver_says "bats:a")" == "unknown" ]]; then
  pass_msg "the resolver revoked bats:a after its source gained a lock"
else
  fail_msg "the resolver still reports $(_resolver_says "bats:a") after a lock was added"
fi
# It must have RUN and isolated, not merely failed to run: a scheduler that
# bails out early would satisfy a naive "did not batch" check while proving
# nothing.
sched_out="$(bash "$SCHED" dispatch --project-root "$PROJ" --run-id c2 \
              --units-json "$PROJ/units.json" --mode observe_parallel --max-workers 4 2>/dev/null)"
if [[ -z "$sched_out" ]]; then
  fail_msg "the scheduler produced no batch at all — this proves nothing about the revocation"
elif [[ "$(jq -r '(.units[] | select(.unit_id=="bats:a") | .co_scheduled_with) | length' <<<"$sched_out")" -eq 0 ]]; then
  pass_msg "the scheduler ran and isolated the revoked unit — one authority, one answer"
else
  fail_msg "the scheduler STILL batches a unit the resolver revoked — the second authority is back"
fi

echo "TEST: the scheduler reads no raw parallel.status"
# The grep is the point: a future edit that reintroduces the raw read is what
# made the two consumers disagree in the first place.
if grep -nE '\$ru\.parallel\.status|\.parallel\.status\)' "$SCHED" | grep -v '^\s*#' | grep -q .; then
  fail_msg "aid-test-scheduler.sh still reads .parallel.status directly: $(grep -nE '\$ru\.parallel\.status' "$SCHED" | head -1)"
else
  pass_msg "aid-test-scheduler.sh resolves through the shared map, never the raw field"
fi

echo "TEST: the effective-status map is computed in ONE pass"
# Counting yq invocations: the per-unit form cost one catalog parse each, which
# is what made this check too slow to keep on the hot path.
_catalog safe safe
YQ_TRACE="$WORK/yq-calls"
: > "$YQ_TRACE"
mkdir -p "$WORK/bin"
cat > "$WORK/bin/yq" <<EOF
#!/usr/bin/env bash
echo call >> "$YQ_TRACE"
exec $(command -v yq) "\$@"
EOF
chmod +x "$WORK/bin/yq"
PATH="$WORK/bin:$PATH" bash -c "
  source '${PLUGIN_DIR}/scripts/lib/aid-test-catalog-provenance.sh'
  aid_test_catalog_effective_status_map '$PROJ/.aid-o/config/test-catalog.yaml' '$PROJ'" >/dev/null 2>&1
YQ_CALLS="$(wc -l < "$YQ_TRACE")"
# One for the catalog, plus a small constant for the closure pass. The
# regression this guards is O(units), not an exact number.
if [[ "$YQ_CALLS" -le 6 ]]; then
  pass_msg "the map costs ${YQ_CALLS} yq invocation(s) for 2 units — a constant, not one per unit"
else
  fail_msg "the map costs ${YQ_CALLS} yq invocations for 2 units — that scales per unit"
fi

echo "Results: ${pass}/$(( pass + fail )) passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
