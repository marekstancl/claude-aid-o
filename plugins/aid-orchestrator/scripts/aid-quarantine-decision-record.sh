#!/usr/bin/env bash
# aid-quarantine-decision-record.sh — P069 Step 18.
#
# Writes a schema-valid, durable PM decision record for lifting/keeping/
# deferring a quarantined gate's quarantine — ONLY on an explicit PM-
# provided --decision invocation. Never automatic, never inferred from
# evidence content alone: this script itself never edits
# execution.yaml's quarantine: block — the decision record is evidence
# for a PM/implementer to act on separately (Constraint 9).
#
# Auto-discovers (never requires the PM to type an exact path) the most
# recently modified, schema-valid evidence from each of Step 15's
# quarantine-remediation bundles and Step 17's E2E full-path proofs
# (restricted to scenario:observe_parallel_full_path, pass:true — a
# failing or wrong-scenario E2E artifact is never silently accepted as
# grounds for a decision). Both must resolve and validate before any
# record is written; a missing or invalid evidence source fails closed.
#
# Supersession guard: a second invocation for the SAME gate_id, without an
# explicit --supersede <prior-decided_at> naming the CURRENT unsuperseded
# leaf record, is refused — --supersede must match the unique leaf (a
# decided_at never named by any record's own supersedes field), never an
# arbitrary historical/already-superseded ancestor (which would fork the
# chain). The superseded record is never deleted, only the new one's own
# `supersedes` field marks it as current. Every candidate existing record
# is schema-validated and gate_id-checked before it counts as part of the
# chain — a malformed stray file fails closed (manual resolution required)
# rather than being silently ignored in either direction. Discovery-through-
# write is serialized per (project_root, gate_id) via an flock on
# .aid-o/work/evidence/quarantine-decisions/.gate-<gate_id>.lock, so two
# concurrent invocations racing to supersede the same leaf cannot both
# succeed and fork the chain.
#
# Usage:
#   aid-quarantine-decision-record.sh --project-root <path> --gate-id bats_all \
#     --decision lift|keep|defer --reviewed-by <name> --rationale <text> \
#     [--supersede <prior-decided_at>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="$(cd "${SCRIPT_DIR}/../defaults/schemas" && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"

DECISION_SCHEMA="${SCHEMAS_DIR}/quarantine-decision.schema.json"
REMEDIATION_SCHEMA="${SCHEMAS_DIR}/quarantine-remediation-evidence.schema.json"
E2E_SCHEMA="${SCHEMAS_DIR}/e2e-full-path-proof.schema.json"

_die() { echo "aid-quarantine-decision-record.sh: $2" >&2; exit "$1"; }

project_root="" gate_id="bats_all" decision="" reviewed_by="" rationale="" supersede=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --gate-id) [[ $# -ge 2 ]] || _die 2 "--gate-id requires a value"; gate_id="$2"; shift 2 ;;
    --decision) [[ $# -ge 2 ]] || _die 2 "--decision requires a value"; decision="$2"; shift 2 ;;
    --reviewed-by) [[ $# -ge 2 ]] || _die 2 "--reviewed-by requires a value"; reviewed_by="$2"; shift 2 ;;
    --rationale) [[ $# -ge 2 ]] || _die 2 "--rationale requires a value"; rationale="$2"; shift 2 ;;
    --supersede) [[ $# -ge 2 ]] || _die 2 "--supersede requires a value"; supersede="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$project_root" ]] || _die 2 "--project-root is required"
project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 3 "--project-root '$project_root' does not exist (or is not a directory)"
[[ -n "$decision" ]] || _die 2 "--decision is required (lift|keep|defer)"
case "$decision" in lift|keep|defer) ;; *) _die 2 "--decision must be lift|keep|defer (got '$decision')" ;; esac
[[ -n "$reviewed_by" ]] || _die 2 "--reviewed-by is required — no partial record is ever written"
[[ -n "$rationale" ]] || _die 2 "--rationale is required — no partial record is ever written"
# Codex re-review (MEDIUM): the schema's format:date-time is NOT semantically
# enforced by this project's validator (no rfc3339-validator installed — see
# quarantine-decision.schema.json's own $comment), so a lexically-shaped but
# nonsensical value ("2026-99-99T99:99:99.000Z") would otherwise pass schema
# validation unnoticed. decided_at itself is always machine-generated below
# (never hand-authored), so the ONE externally-supplied date-like value this
# script accepts is --supersede — validated semantically here with `date -d`,
# which closes the actual exploitable path even though the shared schema
# validator's format-checking gap remains a pre-existing, out-of-scope
# limitation for every OTHER schema in this plan.
if [[ -n "$supersede" ]] && ! date -u -d "$supersede" >/dev/null 2>&1; then
  _die 2 "--supersede '${supersede}' is not a semantically valid date-time — refusing to accept a lexically-shaped but nonsensical timestamp"
fi

remediation_dir="${project_root}/.aid-o/work/evidence/quarantine-remediation"
e2e_dir="${project_root}/.aid-o/work/evidence/e2e-full-path-proof"
decisions_dir="${project_root}/.aid-o/work/evidence/quarantine-decisions"
mkdir -p "$decisions_dir"

# Codex re-review (HIGH): without serialization, two concurrent invocations
# can both observe the same current leaf, both pass the --supersede check,
# and both write a new record — producing a fork despite the leaf-only
# guard below (which is only correct for SEQUENTIAL invocations). This lock
# spans discovery-of-existing-records through the final write + git add, so
# only one invocation at a time can observe-and-extend the chain for a given
# gate_id in a given project.
lock_file="${decisions_dir}/.gate-${gate_id}.lock"
exec 9>"$lock_file"
flock -x 9

# ─── Auto-discover Step 15's remediation evidence (newest mtime, schema-valid) ──
# Codex review (MEDIUM): the filename glob alone ("${gate_id}-*.json") only
# constrains WHERE the file lives, not what gate it actually documents — a
# schema-valid bundle for a DIFFERENT gate, renamed to match this glob,
# would previously have been silently accepted. The document's own
# .gate_id field is now checked explicitly, not just its filename.
evidence_ref=""
if [[ -d "$remediation_dir" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    json="$(jq -c '.' "$f" 2>/dev/null)" || continue
    adapter_validate_schema "$REMEDIATION_SCHEMA" "$json" >/dev/null 2>&1 || continue
    [[ "$(jq -r '.gate_id // empty' <<<"$json")" == "$gate_id" ]] || continue
    evidence_ref="$f"
    break
  done < <(find "$remediation_dir" -maxdepth 1 -name "${gate_id}-*.json" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
fi
[[ -n "$evidence_ref" ]] || _die 1 "no schema-valid quarantine-remediation-evidence bundle found for gate_id '${gate_id}' under ${remediation_dir} — run Step 15's collector first"

# ─── Auto-discover Step 17's E2E proof (newest mtime, scenario+pass+schema-valid) ──
e2e_evidence_ref=""
if [[ -d "$e2e_dir" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    json="$(jq -c '.' "$f" 2>/dev/null)" || continue
    [[ "$(jq -r '.scenario // empty' <<<"$json")" == "observe_parallel_full_path" ]] || continue
    [[ "$(jq -r '.pass // false' <<<"$json")" == "true" ]] || continue
    adapter_validate_schema "$E2E_SCHEMA" "$json" >/dev/null 2>&1 || continue
    e2e_evidence_ref="$f"
    break
  done < <(find "$e2e_dir" -maxdepth 1 -name "*.json" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
fi
[[ -n "$e2e_evidence_ref" ]] || _die 1 "no schema-valid, pass:true observe_parallel_full_path E2E proof found under ${e2e_dir} — run Step 17's E2E script first"

# EPIC 5 whole-diff review (HIGH): both refs were being stored as absolute
# filesystem paths (derived from --project-root), which the decision record
# then force-tracks into git — permanently embedding the creating
# workstation/worktree's own path into a durable, portable artifact that
# would no longer resolve after a fresh clone or worktree relocation.
# Stored (and displayed) project_root-relative instead, matching the
# schemas' own documented ".aid-o/work/evidence/..."-relative convention.
evidence_ref="${evidence_ref#"${project_root}"/}"
e2e_evidence_ref="${e2e_evidence_ref#"${project_root}"/}"

echo "Evidence presented for this decision:"
echo "  evidence_ref:     ${evidence_ref}"
echo "  e2e_evidence_ref: ${e2e_evidence_ref}"

# ─── Supersession guard ────────────────────────────────────────────────
# Codex review findings, all fixed here together (they compound — fixing
# one without the others reopens the gap):
#   HIGH  — a bare "does --supersede match ANY existing decided_at" check
#           let a NEW record fork off an already-superseded ancestor
#           (A -> B, then a second "A -> C" — B and C both look
#           authoritative afterwards). Fixed by computing the unique
#           current LEAF (a decided_at not named by any record's own
#           supersedes field) and requiring --supersede to match THAT
#           leaf specifically, never an arbitrary historical record.
#   MEDIUM — --supersede was accepted even with zero existing records,
#           emitting a dangling reference. Fixed: --supersede is refused
#           outright when no record exists yet for gate_id.
#   MEDIUM — every file matching the glob was treated as an existing
#           record without schema validation; a malformed stray file
#           could either wrongly block every future decision (no
#           --supersede could ever "match" it) or, if hand-crafted with a
#           matching decided_at, wrongly authorize a supersession. Fixed:
#           every candidate is schema-validated and gate_id-checked
#           before it counts as part of the chain; any non-conforming
#           file under the gate_id's own naming pattern is a hard,
#           fail-closed error (manual resolution required) rather than
#           silently ignored either way.
existing_records_json="[]"
if [[ -d "$decisions_dir" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    json="$(jq -c '.' "$f" 2>/dev/null)" || _die 1 "existing decision record '${f}' is not valid JSON — refusing to write until this is resolved manually"
    adapter_validate_schema "$DECISION_SCHEMA" "$json" >/dev/null 2>&1 \
      || _die 1 "existing decision record '${f}' is not schema-valid — refusing to write until this is resolved manually (do not silently ignore a malformed decision record)"
    [[ "$(jq -r '.gate_id // empty' <<<"$json")" == "$gate_id" ]] \
      || _die 1 "existing decision record '${f}' matches the '${gate_id}-*.json' naming pattern but its own gate_id field disagrees — refusing to write until this is resolved manually"
    existing_records_json="$(jq -c --argjson r "$json" --arg path "$f" '. + [$r + {_path:$path}]' <<<"$existing_records_json")"
  done < <(find "$decisions_dir" -maxdepth 1 -name "${gate_id}-*.json" 2>/dev/null | sort)
fi

existing_count="$(jq 'length' <<<"$existing_records_json")"
if [[ "$existing_count" -gt 0 ]]; then
  # Leaf = a decided_at never named by any record's own supersedes field.
  leaves_json="$(jq -c '
    ([.[].supersedes // empty]) as $superseded
    | [.[] | select(([.decided_at] - $superseded) | length > 0)]
  ' <<<"$existing_records_json")"
  leaf_count="$(jq 'length' <<<"$leaves_json")"
  if [[ "$leaf_count" -eq 0 ]]; then
    _die 1 "gate_id '${gate_id}' has ${existing_count} existing decision record(s) but no unsuperseded leaf could be found (a supersedes cycle?) — refusing to write, resolve manually"
  elif [[ "$leaf_count" -gt 1 ]]; then
    leaf_list="$(jq -r '.[]._path' <<<"$leaves_json" | tr '\n' ' ')"
    _die 1 "gate_id '${gate_id}' has ${leaf_count} independent unsuperseded decision records (${leaf_list}) — a fork exists; refusing to write until this is resolved manually by superseding down to a single leaf"
  fi
  leaf_decided_at="$(jq -r '.[0].decided_at' <<<"$leaves_json")"
  leaf_path="$(jq -r '.[0]._path' <<<"$leaves_json")"
  if [[ -z "$supersede" ]]; then
    _die 1 "an existing decision record for gate_id '${gate_id}' already exists (current: ${leaf_path}) — refusing to write a second, conflicting record without --supersede <prior-decided_at>"
  fi
  [[ "$supersede" == "$leaf_decided_at" ]] \
    || _die 1 "--supersede '${supersede}' does not match the CURRENT unsuperseded decision record's decided_at ('${leaf_decided_at}', ${leaf_path}) for gate_id '${gate_id}' — refusing to write (a new record may only supersede the current leaf, never an already-superseded ancestor)"
elif [[ -n "$supersede" ]]; then
  _die 1 "--supersede '${supersede}' given but no existing decision record exists for gate_id '${gate_id}' — refusing to write a dangling supersedes reference"
fi

# Codex review (HIGH): whole-second precision let two invocations within the
# same wall-clock second derive the identical filename, silently destroying
# the prior record on write — the opposite of "never overwritten". Millisecond
# precision (matches the schema's own pattern) makes same-filename collisions
# vanishingly unlikely; the explicit -f/-e guard on out_path below closes the
# remainder rather than relying on timing alone.
decided_at="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null)"
if [[ ! "$decided_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$ ]]; then
  ns="$(date -u +%N)"
  decided_at="$(date -u +%Y-%m-%dT%H:%M:%S).${ns:0:3}Z"
fi
record_json="$(jq -n \
  --arg gid "$gate_id" --arg ev "$evidence_ref" --arg e2e "$e2e_evidence_ref" \
  --arg dec "$decision" --arg rb "$reviewed_by" --arg da "$decided_at" \
  --arg rat "$rationale" --arg sup "$supersede" \
  '{gate_id:$gid, evidence_ref:$ev, e2e_evidence_ref:$e2e, decision:$dec,
    reviewed_by:$rb, decided_at:$da, rationale:$rat}
   + (if $sup != "" then {supersedes:$sup} else {} end)')"

adapter_validate_schema "$DECISION_SCHEMA" "$record_json" \
  || _die 1 "internal error: assembled decision record failed schema validation — refusing to write"

safe_decided_at="${decided_at//:/}"
out_path="${decisions_dir}/${gate_id}-${safe_decided_at}.json"
# The flock held since before existing-record discovery (above) makes this
# check race-free: only one invocation at a time can reach this point for
# a given gate_id, so an "already exists" hit here is genuine corruption,
# never a TOCTOU false-negative from a concurrent writer.
[[ -e "$out_path" ]] && _die 1 "internal error: ${out_path} already exists — refusing to overwrite an existing decision record (this should be structurally impossible given millisecond-precision decided_at; treat as corruption and resolve manually)"
echo "$record_json" | jq '.' > "$out_path"

if git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
  rel="${out_path#"${project_root}"/}"
  git -C "$project_root" add -f -- "$rel"
  echo "aid-quarantine-decision-record.sh: wrote and force-tracked ${rel} (decision:${decision}${supersede:+, supersedes:${supersede}})"
else
  echo "aid-quarantine-decision-record.sh: not a git repository, record written to ${out_path} but not tracked"
fi
