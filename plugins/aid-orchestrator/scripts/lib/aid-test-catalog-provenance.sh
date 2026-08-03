#!/usr/bin/env bash
# aid-test-catalog-provenance.sh — P072 Step 16.
#
# `parallel.status` decides whether a test file runs concurrently with others.
# Before this, it was a field nobody read: the lane runner consulted a separate
# text allowlist instead, so the catalog said one thing and the runner did
# another. Two authorities over one question is how a promotion outlives the
# evidence behind it.
#
# This library makes the field mean something checkable, and gives every
# consumer ONE function to call.
#
# THE TWO-TIER REVERSION RULE
#   A recorded status is bound to the content it was verified against.
#
#     source hash matches            -> the recorded status stands
#     source hash differs, but the
#       resource digest is unchanged -> the status stands, hash refreshed
#     resource digest also changed   -> `unknown`
#     a source path is gone          -> `unknown`
#
#   The middle case is why this is two-tier rather than one. A comment edit
#   changes the file's bytes and nothing else; reverting on that alone would
#   cost a full pilot for a typo fix, and a rule that expensive gets disabled.
#   A change that adds a lock, a port, or another shared path changes the
#   resource digest — including when a resource of that same class was already
#   present, because the digest covers each resource's identifying detail and
#   not merely its kind.
#
# WHY EVERY CALLER MUST USE effective_status
#   The reversion rule is not something a caller can be trusted to remember.
#   Reading `.parallel.status` directly is always wrong, and this file exists
#   so that there is no reason to.
#
# Function results are echoed; exit status is 0 unless stated.

set -uo pipefail

_TCP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-test-audit-config.sh
source "${_TCP_LIB_DIR}/aid-test-audit-config.sh"

# aid_test_catalog_provenance_hash <run_unit_id> <catalog> <project_root>
#
# SHA-256 over the concatenated contents of the unit's source_paths, in CATALOG
# ORDER. Order is part of the identity: a multi-file unit whose sources are
# reordered is a different composition, and a reversion that costs one
# re-verification is the safe direction to be wrong in.
#
# Echoes the digest, or `missing_source` when a declared path is gone.
aid_test_catalog_provenance_hash() {
  local unit_id="$1" catalog="$2" project_root="$3"
  local unit paths p abs
  unit="$(yq -o=json '.' "$catalog" 2>/dev/null \
          | jq -c --arg id "$unit_id" '.run_units[] | select(.run_unit_id == $id)')" || return 1
  [[ -n "$unit" ]] || { echo "unknown_unit"; return 1; }

  mapfile -t paths < <(jq -r '(.source_paths // [])[]' <<<"$unit")
  [[ "${#paths[@]}" -gt 0 ]] && [[ -n "${paths[0]}" ]] || { echo "missing_source"; return 0; }

  # Each path contributes its NAME and its LENGTH as well as its bytes. Raw
  # concatenation let a unit swap `[a.bats, helper.bash]` for
  # `[new-unsafe.bats, copied-helper.bash]` while preserving the byte stream,
  # and the hash still matched — so the lane would run a different executable
  # file under a status verified for the old one.
  local tmp; tmp="$(mktemp)"
  for p in "${paths[@]}"; do
    abs="$p"; [[ "$abs" = /* ]] || abs="${project_root%/}/${p}"
    if [[ ! -f "$abs" ]]; then rm -f "$tmp"; echo "missing_source"; return 0; fi
    printf 'path:%s\nbytes:%s\n' "$p" "$(wc -c < "$abs" | tr -d ' ')" >> "$tmp"
    cat "$abs" >> "$tmp"
    printf '\n--aid-source-boundary--\n' >> "$tmp"
  done
  sha256sum "$tmp" | cut -d' ' -f1
  rm -f "$tmp"
}

# aid_test_catalog_provenance_resource_digest <run_unit_id> <catalog> <project_root>
#
# SHA-256 over the unit's sorted `kind/namespace/detail` triples from the Step
# 14 map.
#
# `detail` is included because the pair alone is far too coarse: a unit that
# already wrote one shared path and then starts writing a SECOND one has the
# same `fixed_path/shared` pair, so a pair-only digest was unchanged and the
# unit kept its `safe` status while its sharing proposition had changed
# completely. The same held for a second lock or a second port.
#
# What is still deliberately excluded: LOCATION and ordering. A resource that
# moved from line 40 to line 50 is the same resource, and reverting on that
# would make the two-tier rule as expensive as the one-tier rule it replaces.
aid_test_catalog_provenance_resource_digest() {
  local unit_id="$1" catalog="$2" project_root="$3"
  local map
  map="$(bash "${_TCP_LIB_DIR}/../aid-test-resource-map.sh" \
          --run-unit-id "$unit_id" --catalog "$catalog" --project-root "$project_root" 2>/dev/null)" \
    || { echo "unavailable"; return 0; }
  jq -r '[.resources[] | .kind + "/" + .namespace + "/" + (.detail // "")] | sort | unique | join("\n")' <<<"$map" \
    | sha256sum | cut -d' ' -f1
}

# aid_test_catalog_provenance_verify <run_unit_id> <catalog> <project_root>
#   echoes: match | mismatch | missing_source | no_provenance
aid_test_catalog_provenance_verify() {
  local unit_id="$1" catalog="$2" project_root="$3"
  local recorded current
  recorded="$(yq -o=json '.' "$catalog" 2>/dev/null \
    | jq -r --arg id "$unit_id" \
      '.run_units[] | select(.run_unit_id == $id) | .parallel.provenance.source_sha256 // "null"')"
  [[ -n "$recorded" && "$recorded" != "null" ]] || { echo "no_provenance"; return 0; }

  current="$(aid_test_catalog_provenance_hash "$unit_id" "$catalog" "$project_root")"
  case "$current" in
    missing_source) echo "missing_source" ;;
    "$recorded")    echo "match" ;;
    *)              echo "mismatch" ;;
  esac
}

# aid_test_catalog_provenance_effective_status <run_unit_id> <catalog> <project_root> [budget_ms]
#
# THE function. Echoes the status a consumer may act on, applying the reversion
# rule above. Never echoes a status it did not verify.
#
# The `mismatch` branch recomputes the resource digest, which is a static
# source read with no test execution. When that cannot be completed within the
# budget, this fails closed to `unknown` rather than retaining a status it did
# not check.
aid_test_catalog_provenance_effective_status() {
  local unit_id="$1" catalog="$2" project_root="$3" budget_ms="${4:-}"
  local recorded_status verdict

  recorded_status="$(yq -o=json '.' "$catalog" 2>/dev/null \
    | jq -r --arg id "$unit_id" \
      '.run_units[] | select(.run_unit_id == $id) | .parallel.status // "unknown"')"
  [[ -n "$recorded_status" ]] || recorded_status="unknown"

  # Nothing to protect: `unknown` is already the fail-closed value.
  [[ "$recorded_status" == "unknown" ]] && { echo "unknown"; return 0; }

  verdict="$(aid_test_catalog_provenance_verify "$unit_id" "$catalog" "$project_root")"
  case "$verdict" in
    match)          echo "$recorded_status"; return 0 ;;
    missing_source) echo "unknown"; return 0 ;;
    no_provenance)
      # A status with no provenance predates this rule. It is not evidence.
      echo "unknown"; return 0 ;;
  esac

  # mismatch: the bytes changed. Did the RESOURCES?
  if [[ -z "$budget_ms" ]]; then
    budget_ms="$(test_audit_decision_key provenance_recheck_budget_ms "$project_root" 2>/dev/null || echo 5000)"
  fi
  [[ "$budget_ms" =~ ^[0-9]+$ ]] || budget_ms=5000

  local recorded_digest current_digest
  recorded_digest="$(yq -o=json '.' "$catalog" 2>/dev/null \
    | jq -r --arg id "$unit_id" \
      '.run_units[] | select(.run_unit_id == $id) | .parallel.provenance.resource_digest // "null"')"
  [[ -n "$recorded_digest" && "$recorded_digest" != "null" ]] || { echo "unknown"; return 0; }

  # The budget is expressed in milliseconds, so honour milliseconds. Rounding
  # up to whole seconds gave a 1ms budget a full second and made the
  # fail-closed path unreachable — a guard that cannot fire is not a guard.
  local budget_s
  budget_s="$(printf '%d.%03d' "$(( budget_ms / 1000 ))" "$(( budget_ms % 1000 ))")"
  current_digest="$(timeout "${budget_s}s" bash -c \
    "source '${_TCP_LIB_DIR}/aid-test-catalog-provenance.sh'; \
     aid_test_catalog_provenance_resource_digest '$unit_id' '$catalog' '$project_root'" 2>/dev/null || echo "timeout")"

  case "$current_digest" in
    timeout|unavailable|"")
      # Not reached in time, or the map could not be built. Fail closed: a
      # status this did not verify is a status it may not echo.
      echo "unknown" ;;
    "$recorded_digest")
      # Bytes moved, resources did not — a comment, a rename, a reflow. The
      # status survives; the caller refreshes the hash.
      echo "$recorded_status" ;;
    *)
      echo "unknown" ;;
  esac
}

# aid_test_catalog_provenance_refresh <run_unit_id> <catalog> <project_root>
#
# Writes the current source hash and a fresh `verified_at` into the catalog for
# a unit whose resources are unchanged. The side effect of the middle tier,
# kept separate so a reader is never surprised by a function that writes.
aid_test_catalog_provenance_refresh() {
  local unit_id="$1" catalog="$2" project_root="$3"
  local h now tmp
  h="$(aid_test_catalog_provenance_hash "$unit_id" "$catalog" "$project_root")"
  [[ "$h" =~ ^[0-9a-f]{64}$ ]] || return 1
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # mikefarah yq takes values through the environment; `--arg` is jq's.
  TCP_ID="$unit_id" TCP_H="$h" TCP_NOW="$now" yq -i '
    (.run_units[] | select(.run_unit_id == strenv(TCP_ID)) | .parallel.provenance.source_sha256) = strenv(TCP_H)
    | (.run_units[] | select(.run_unit_id == strenv(TCP_ID)) | .parallel.provenance.verified_at) = strenv(TCP_NOW)
  ' "$catalog" || return 1
  return 0
}
