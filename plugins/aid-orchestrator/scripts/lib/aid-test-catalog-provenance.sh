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
# SHA-256 over the unit's DEPENDENCY CLOSURE — its declared source_paths plus
# every file reached from them through `source`, `.` and `load` — with each
# file's path and length hashed alongside its bytes.
#
# The closure, and not merely the declared paths, because a status bound only
# to a unit's own file survives its shared helper acquiring a lock: the unit's
# bytes are unchanged, the hash still matches, the resource digest is never
# recomputed, and the unit stays in the parallel pool with a hazard nobody
# looked at. The helper IS part of what was verified, so it is part of what the
# verification is bound to.
#
# Order is part of the identity: declared paths in catalog order first, then
# the rest of the closure sorted, so the result is deterministic while a
# reordering of the declared paths still changes it.
#
# Echoes the digest, `missing_source` when a path is gone, or
# `unresolved_closure` when a dependency could not be read — the latter being a
# closure this cannot claim to have hashed.
# aid_test_catalog_provenance_hash_from_closure <unit_id> <catalog> <project_root> <closure_file>
#
# The same digest, over a closure someone else already computed. The batch
# resolver builds every unit's closure in ONE pass; without this, each unit
# would still shell out to the map builder and the batch would save nothing.
# <unit_id> <declared_paths_newline_separated> <project_root> <closure_file>
#
# Takes the declared paths rather than re-reading the catalog: parsing YAML
# once per unit was 65 `yq` invocations on the hot path, which is most of what
# batching was supposed to remove.
aid_test_catalog_provenance_hash_from_closure() {
  local unit_id="$1" declared="$2" project_root="$3" closure_file="$4"
  # Declared paths in CATALOG ORDER first, then the rest of the closure sorted
  # — byte-identical ordering to the non-batch function, or a migrated hash
  # computed by one would never match a check made by the other.
  local -a paths=()
  mapfile -t paths < <(printf '%s\n' "$declared" | grep -v '^$' || true)
  [[ "${#paths[@]}" -gt 0 && -n "${paths[0]}" ]] || { echo "missing_source"; return 0; }

  local line extra known seen
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in
      unresolved:*) echo "unresolved_closure"; return 0 ;;
    esac
  done < "$closure_file"
  while IFS= read -r extra; do
    [[ -z "$extra" ]] && continue
    seen=0
    for known in "${paths[@]}"; do [[ "$known" == "$extra" ]] && seen=1; done
    [[ "$seen" -eq 0 ]] && paths+=("$extra")
  done < <(grep -v '^unresolved:' "$closure_file" | sort)

  local tmp; tmp="$(mktemp)"
  local p abs
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

aid_test_catalog_provenance_hash() {
  local unit_id="$1" catalog="$2" project_root="$3"
  local unit paths p abs
  unit="$(yq -o=json '.' "$catalog" 2>/dev/null \
          | jq -c --arg id "$unit_id" '.run_units[] | select(.run_unit_id == $id)')" || return 1
  [[ -n "$unit" ]] || { echo "unknown_unit"; return 1; }

  mapfile -t paths < <(jq -r '(.source_paths // [])[]' <<<"$unit")
  [[ "${#paths[@]}" -gt 0 ]] && [[ -n "${paths[0]}" ]] || { echo "missing_source"; return 0; }

  # Extend the declared paths with the rest of the closure.
  local closure extra
  closure="$(bash "${_TCP_LIB_DIR}/../aid-test-resource-map.sh" --files-only \
              --run-unit-id "$unit_id" --catalog "$catalog" --project-root "$project_root" 2>/dev/null || true)"
  if grep -q '^unresolved:' <<<"$closure" 2>/dev/null; then
    echo "unresolved_closure"; return 0
  fi
  if [[ -n "$closure" ]]; then
    while IFS= read -r extra; do
      [[ -z "$extra" ]] && continue
      local seen=0 known
      for known in "${paths[@]}"; do [[ "$known" == "$extra" ]] && seen=1; done
      [[ "$seen" -eq 0 ]] && paths+=("$extra")
    done < <(printf '%s\n' "$closure" | sort)
  fi

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
    missing_source)     echo "missing_source" ;;
    unresolved_closure) echo "missing_source" ;;
    "$recorded")        echo "match" ;;
    *)                  echo "mismatch" ;;
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

# ─── The one resolver every consumer uses ───────────────────────────────────
#
# aid_test_catalog_effective_status_map <catalog> <project_root> [overlay_json]
#
# Echoes {run_unit_id: effective_status} for every unit in the catalog, with the
# provenance reversion rule applied — and, when a scheduler overlay is supplied,
# with that overlay applied ON TOP but never ABOVE it.
#
# WHY THE PRIORITY IS THAT WAY ROUND
#   `unknown` covers two different situations, and they must not be treated
#   alike:
#
#     NEVER VERIFIED — the catalog records `unknown` because nobody has
#       assessed this unit. An overlay entry is exactly the PM-approved
#       promotion that is meant to resolve that, and it carries its own
#       freshness check (`catalog_fingerprint_at_promotion`). It may promote.
#
#     REVOKED — the catalog records something stronger, but the content has
#       moved since it was verified. Here an overlay entry is vouching for
#       content it never saw, and letting it promote would reintroduce the
#       second authority this work removed. It may NOT promote.
#
#   So provenance is a floor for what it has actually assessed: an overlay can
#   promote a unit provenance never judged, and can never rescue one it
#   revoked.
#
# Consumers must call THIS rather than reading `.parallel.status`, because a
# raw read skips both rules and the two consumers that did it disagreed with
# the lane runner about the same unit.
# A fourth argument restricts resolution to a named subset (newline-separated
# ids in a file). Units outside it report `unknown` rather than their recorded
# value, because this call did not verify them. That matters for cost: a
# closure hash per unit across a whole pool is minutes, and a check that
# expensive on a hot path is a check that gets skipped.
aid_test_catalog_effective_status_map() {
  local catalog="$1" project_root="$2" overlay_json="${3:-}" only_file="${4:-}"
  local catalog_json
  catalog_json="$(yq -o=json '.' "$catalog" 2>/dev/null)" || { echo '{}'; return 1; }

  # `unknown` needs no work and is already the fail-closed value, so only the
  # units claiming something stronger are resolved.
  local claiming
  claiming="$(jq -r '.run_units[] | select((.parallel.status // "unknown") != "unknown") | .run_unit_id' <<<"$catalog_json")"
  if [[ -n "$only_file" && -f "$only_file" ]]; then
    claiming="$(grep -xF -f "$only_file" <<<"$claiming" || true)"
  fi

  local resolved='{}' revoked='[]'
  if [[ -n "$claiming" ]]; then
    # ── ONE pass, one shared budget ──────────────────────────────────────
    #
    # The first cut re-parsed the catalog and shelled out to the map builder
    # once PER UNIT: 101 seconds to partition this repository's own pool, on a
    # path that runs before every gate. A check that expensive is a check
    # somebody disables. The plan asked for a batch pass and a shared budget,
    # and this is it.
    local budget_ms="${_TCP_BATCH_BUDGET_MS:-}"
    [[ -n "$budget_ms" ]] || budget_ms="$(test_audit_decision_key provenance_recheck_budget_ms "$project_root" 2>/dev/null || echo 5000)"
    [[ "$budget_ms" =~ ^[0-9]+$ ]] || budget_ms=5000

    local work; work="$(mktemp -d)"
    printf '%s\n' "$claiming" > "$work/units.txt"
    : > "$work/resolved.tsv"

    # Closures for EVERY claiming unit, in a single process.
    bash "${_TCP_LIB_DIR}/../aid-test-resource-map.sh" --files-only \
      --units-from "$work/units.txt" --catalog "$catalog" --project-root "$project_root" \
      > "$work/closures.tsv" 2>/dev/null || : > "$work/closures.tsv"

    # The budget governs the DIGEST RECHECKS — the expensive part, and the one
    # the plan names. Hashing is cheap and must happen for every claiming unit:
    # applying the budget to it too meant the first few units consumed it and
    # every later one fell to `unknown`, which is fail-closed but useless.
    local deadline_ms=$(( $(date +%s%N) / 1000000 + budget_ms ))
    local uid eff recorded_hash current_hash recorded_digest current_digest declared

    # One pass over the catalog for every field this loop needs.
    jq -r '.run_units[]
           | .run_unit_id + "\t" + (.parallel.status // "unknown")
             + "\t" + (.parallel.provenance.source_sha256 // "null")
             + "\t" + (.parallel.provenance.resource_digest // "null")
             + "\t" + ((.source_paths // []) | join(","))' <<<"$catalog_json" > "$work/fields.tsv"

    while IFS= read -r uid; do
      [[ -z "$uid" ]] && continue

      IFS=$'\t' read -r _ eff recorded_hash recorded_digest declared \
        < <(awk -F'\t' -v u="$uid" '$1 == u { print; exit }' "$work/fields.tsv")
      declared="${declared//,/$'\n'}"

      awk -F'\t' -v u="$uid" '$1 == u { print $2 }' "$work/closures.tsv" > "$work/one.txt"
      if [[ -z "$recorded_hash" || "$recorded_hash" == "null" ]]; then
        # No provenance is not evidence.
        printf '%s\tunknown\trevoked\n' "$uid" >> "$work/resolved.tsv"
        continue
      fi

      current_hash="$(aid_test_catalog_provenance_hash_from_closure "$uid" "$declared" "$project_root" "$work/one.txt")"
      if [[ "$current_hash" == "$recorded_hash" ]]; then
        printf '%s\t%s\tkept\n' "$uid" "$eff" >> "$work/resolved.tsv"
        continue
      fi

      # The bytes moved. Only NOW is the expensive digest worth computing, and
      # only for this unit — which is why the common case costs one process for
      # the whole pool rather than one per member.
      if [[ -z "$recorded_digest" || "$recorded_digest" == "null" ]]; then
        printf '%s\tunknown\trevoked\n' "$uid" >> "$work/resolved.tsv"
        continue
      fi

      local remaining_ms=$(( deadline_ms - $(date +%s%N) / 1000000 ))
      if [[ "$remaining_ms" -le 0 ]]; then
        printf '%s\tunknown\trevoked\n' "$uid" >> "$work/resolved.tsv"
        continue
      fi
      current_digest="$(timeout "$(printf '%d.%03d' "$(( remaining_ms / 1000 ))" "$(( remaining_ms % 1000 ))")s" \
        bash -c "source '${_TCP_LIB_DIR}/aid-test-catalog-provenance.sh'; \
                 aid_test_catalog_provenance_resource_digest '$uid' '$catalog' '$project_root'" 2>/dev/null || echo timeout)"

      if [[ "$current_digest" == "$recorded_digest" ]]; then
        printf '%s\t%s\tkept\n' "$uid" "$eff" >> "$work/resolved.tsv"
      else
        printf '%s\tunknown\trevoked\n' "$uid" >> "$work/resolved.tsv"
      fi
    done <<< "$claiming"

    # One conversion, not one per unit.
    if [[ -s "$work/resolved.tsv" ]]; then
      resolved="$(awk -F'\t' '{printf "%s\n%s\n", $1, $2}' "$work/resolved.tsv" \
                   | jq -Rc -s 'split("\n") | map(select(length > 0))
                                | . as $f | [range(0; length; 2) | {($f[.]): $f[.+1]}] | add // {}')"
      revoked="$(awk -F'\t' '$3 == "revoked" { print $1 }' "$work/resolved.tsv" \
                   | jq -Rc -s 'split("\n") | map(select(length > 0))')"
    fi

    rm -rf "$work"
  fi

  jq -c --argjson resolved "$resolved" --argjson revoked "$revoked" --argjson ov "${overlay_json:-null}" '
    [ .run_units[]
      | .run_unit_id as $uid
      | ($resolved[$uid] // "unknown") as $prov
      | ( if $ov == null or ($ov.status // "") != "approved" then $prov
          else ( ($ov.overlay // [] | map(select(.run_unit_id == $uid)) | .[0]) as $entry
                 | if $entry == null then $prov
                   elif $entry.catalog_fingerprint_at_promotion != (.runtime.fingerprint // "") then $prov
                   # REVOKED, not merely unassessed: the unit claimed a status
                   # and its content has since moved. An overlay cannot vouch
                   # for content it never saw.
                   elif ($revoked | index($uid)) then "unknown"
                   else ($entry.promoted_status // $prov)
                   end )
          end ) as $eff
      | {($uid): $eff} ]
    | add // {}' <<<"$catalog_json"
}
