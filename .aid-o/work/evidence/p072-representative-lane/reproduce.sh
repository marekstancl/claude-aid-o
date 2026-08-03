#!/usr/bin/env bash
# Step 18 dogfood: pilot a representative lane of THIS repository's own bats
# units, serially and concurrently, in a disposable clone.
set -uo pipefail
REPO=/opt/eco/projects/aid-orchestrator
SP=/tmp/claude-1000/-opt-eco-projects-aid-orchestrator/fceea7f1-bc28-44a6-8212-974e4b4cda61/scratchpad
C="$SP/lane-clone"; OUT="$SP/lane-out"
rm -rf "$C" "$OUT"
git clone -q "$REPO" "$C"
mkdir -p "$C/.aid-o/config"
cp "$REPO"/.aid-o/config/{test-catalog.yaml,execution.yaml,test-audit.yaml} "$C/.aid-o/config/" 2>/dev/null

# A representative lane: four pooled units of moderate, comparable cost.
UNITS=(
  "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary"
  "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-gate-runtime-report"
  "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-gitignore-backfill"
  "bats:plugins/aid-orchestrator/scripts/tests/bats/test-delivery-report"
)
ARGS=(); for u in "${UNITS[@]}"; do ARGS+=(--unit "$u"); done

R="$(bash "$REPO/plugins/aid-orchestrator/scripts/aid-test-parallel-pilot.sh" \
  --lane-id "representative-lane" "${ARGS[@]}" \
  --catalog "$C/.aid-o/config/test-catalog.yaml" \
  --execution-yaml "$C/.aid-o/config/execution.yaml" \
  --output-dir "$OUT" --audit-id "dogfood-1" \
  --target-root "$C" --project-root "$REPO" \
  --workers 4 --repeat 2 --deadline 1200)"
echo "receipt: $R"
jq '{promotion, reason, benefit_ms, noise_threshold_ms, workers, repeat,
     membership, parallelism,
     repetitions: [.repetitions[] | {index, verdict,
        serial_ms: .serial.duration_ms, parallel_ms: .parallel.duration_ms,
        serial_exit: .serial.exit_code, parallel_exit: .parallel.exit_code,
        cases: (.serial.results | length),
        dirty: (.parallel.dirty_paths | length),
        escaped: (.parallel.escaped_paths | length)}]}' "$R"
