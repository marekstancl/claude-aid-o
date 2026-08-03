#!/usr/bin/env bash
# aid-test-catalog-migrate-p071-allowlist.sh — P072 Step 17.
#
# One-shot, idempotent migration of P071 Step 3's real parallel-safety evidence
# out of a text allowlist and into the catalog, where it can be bound to the
# content it was verified against.
#
# WHY THE EVIDENCE MOVES RATHER THAN BEING RE-GATHERED
#   P071 Step 3 really did pilot those files. Discarding that and re-piloting
#   from scratch would spend hours to re-learn what is already known. What the
#   text file could not do is notice that a file it names has since acquired a
#   lock — so the evidence is carried across WITH a source hash and a resource
#   digest, and from then on the reversion rule applies to it like anything
#   else.
#
# WHAT IT REFUSES
#   A listed path with no catalog run unit fails the migration, naming the
#   path. Creating an entry the inventory does not know about would put a file
#   in the pool that no other part of the system can see.
#
# WHAT IT DOES NOT LAUNDER
#   The retiring allowlist's own header states that P066's audit "read all 83
#   bats files". That figure is wrong in both directions — the catalog holds
#   74 bats run units and the tree holds more than that — so the migrated
#   evidence records the REAL counts, measured at migration time, and notes
#   that the header was mistaken. Copying the number across verbatim would
#   turn a documentation error into a durable schema field.
#
# Exit codes: 0 ok · 2 usage · 3 a listed path has no run unit · 4 catalog
#             schema predates the provenance field

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-catalog-provenance.sh
source "${SCRIPT_DIR}/lib/aid-test-catalog-provenance.sh"

_die() { echo "aid-test-catalog-migrate-p071-allowlist.sh: $2" >&2; exit "$1"; }

catalog_path="" allowlist_path="" project_root="" dry_run=0
# P071's release date: when this evidence was actually gathered. Recording
# today's date instead would claim a verification that did not happen today.
P071_VERIFIED_AT="2026-08-02T00:00:00Z"
P071_AUDIT_ID="audit-20260802-070629"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog)      [[ $# -ge 2 ]] || _die 2 "--catalog requires a value"; catalog_path="$2"; shift 2 ;;
    --allowlist)    [[ $# -ge 2 ]] || _die 2 "--allowlist requires a value"; allowlist_path="$2"; shift 2 ;;
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --dry-run)      dry_run=1; shift ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$catalog_path" && -f "$catalog_path" ]] || _die 2 "--catalog is required and must exist"
[[ -n "$project_root" && -d "$project_root" ]] || _die 2 "--project-root is required and must exist"
[[ -n "$allowlist_path" ]] \
  || allowlist_path="${SCRIPT_DIR}/../defaults/config/bats-parallel-safe-allowlist.txt"
[[ -f "$allowlist_path" ]] || _die 2 "--allowlist '$allowlist_path' does not exist"

# The catalog must already understand the field being written. Writing
# provenance into a schema that does not define it would produce a catalog its
# own validator rejects.
if ! jq -e '.["$defs"].parallel.properties.provenance' \
      "${SCRIPT_DIR}/../defaults/schemas/test-catalog.schema.json" >/dev/null 2>&1; then
  _die 4 "the catalog schema has no parallel.provenance definition — run this only against a schema that includes P072 Step 16"
fi

# ─── Resolve every listed path to a run unit, or refuse ─────────────────────
catalog_json="$(yq -o=json '.' "$catalog_path")" || _die 2 "could not read the catalog"

declare -a listed=() unresolved=()
already=""
while IFS= read -r line; do
  line="${line%%#*}"; line="${line//[[:space:]]/}"
  [[ -z "$line" ]] && continue
  listed+=("$line")
done < "$allowlist_path"

if [[ "${#listed[@]}" -eq 0 ]]; then
  # The allowlist has been retired and emptied, which is the END STATE of this
  # migration rather than a broken input. Distinguish the two: if the catalog
  # already carries migrated entries, this is a completed migration re-run and
  # a no-op; if it carries none, someone has emptied the list without ever
  # migrating it, and the evidence is simply gone.
  already="$(jq -r '[.run_units[] | select(.parallel.provenance.method == "migrated_p071_step3")] | length' <<<"$catalog_json")"
  if [[ "$already" -gt 0 ]]; then
    echo "aid-test-catalog-migrate-p071-allowlist.sh: nothing to migrate — the allowlist is retired and the catalog already carries ${already} migrated entries" >&2
    exit 0
  fi
  _die 2 "the allowlist lists no paths and the catalog carries no migrated entries — the P071 evidence is not in either place"
fi

declare -a unit_ids=()
for p in "${listed[@]}"; do
  # The listed path must be the unit's FIRST source path — the .bats file the
  # lane actually executes. Matching anywhere in source_paths let a listed
  # helper vouch for a unit whose executable file was never piloted, and the
  # lane would then pool that file.
  uid="$(jq -r --arg p "$p" \
    '.run_units[] | select(.runner == "bats") | select(((.source_paths // [])[0]) == $p) | .run_unit_id' \
    <<<"$catalog_json")"
  n_match="$(printf '%s\n' "$uid" | grep -c . || true)"
  if [[ -z "$uid" || "$n_match" -ne 1 ]]; then unresolved+=("$p"); else unit_ids+=("$uid"); fi
done

if [[ "${#unresolved[@]}" -gt 0 ]]; then
  echo "aid-test-catalog-migrate-p071-allowlist.sh: ${#unresolved[@]} listed path(s) have no catalog run unit:" >&2
  printf '  - %s\n' "${unresolved[@]}" >&2
  _die 3 "refusing to create catalog entries the inventory does not know about"
fi

# ─── The corrected denominator, measured rather than copied ─────────────────
catalog_bats_units="$(jq -r '[.run_units[] | select(.runner == "bats")] | length' <<<"$catalog_json")"
tree_bats_files="$(find "$project_root" -path '*/.git' -prune -o -name '*.bats' -print 2>/dev/null | wc -l)"
evidence_ref="P071 Step 3 pilot, ${P071_AUDIT_ID}: ${#listed[@]} bats files piloted, out of ${catalog_bats_units} bats run units in the catalog and ${tree_bats_files} .bats files in the tree at migration time. (The retiring allowlist header's figure of 83 was wrong in both directions and is not reproduced here.)"

echo "aid-test-catalog-migrate-p071-allowlist.sh: migrating ${#listed[@]} entries" >&2
echo "  evidence_ref: ${evidence_ref}" >&2

if [[ "$dry_run" -eq 1 ]]; then
  printf '%s\n' "${unit_ids[@]}"
  exit 0
fi

# ─── Write, and warn about drift rather than hiding it ──────────────────────
declare -a drifted=()
p071_commit=""
i=0
for uid in "${unit_ids[@]}"; do
  src_hash="$(aid_test_catalog_provenance_hash "$uid" "$catalog_path" "$project_root")"
  [[ "$src_hash" =~ ^[0-9a-f]{64}$ ]] \
    || _die 3 "could not hash the sources of '$uid' (got '$src_hash') — a migrated entry must be bound to real content"
  res_digest="$(aid_test_catalog_provenance_resource_digest "$uid" "$catalog_path" "$project_root")"
  [[ "$res_digest" =~ ^[0-9a-f]{64}$ ]] \
    || _die 3 "could not compute a resource digest for '$uid' (got '$res_digest')"

  # A file edited since P071 verified it is NOT migrated as safe. Hashing the
  # edited content and writing `status: safe` would bind P071's evidence to
  # bytes P071 never saw — the migration would launder a post-pilot change into
  # fresh-looking evidence, and the lane would pool the changed file.
  #
  # A warning cannot preserve evidence for different content, so the unit is
  # left `unknown` and named. Leaving it out silently would lose a real pool
  # member with no record; this loses it loudly, and re-piloting restores it.
  # Drift is only decidable where there IS a commit from before P071 to compare
  # against. In a project with no such history the check has nothing to say —
  # and absence of history is not evidence of change, so it must not be read as
  # drift. Refusing to migrate on "I cannot tell" would make this unusable in
  # any repository that did not exist in August 2026, including every fixture.
  p071_commit="$(git -C "$project_root" log -1 --format=%H --before="2026-08-02T23:59:59" 2>/dev/null || true)"
  if [[ -n "$p071_commit" ]]; then
    if ! git -C "$project_root" diff --quiet "$p071_commit" -- "${listed[$i]}" 2>/dev/null; then
      drifted+=("${listed[$i]}")
      i=$(( i + 1 ))
      continue
    fi
  fi

  MIG_ID="$uid" MIG_REF="$evidence_ref" MIG_AT="$P071_VERIFIED_AT" \
  MIG_SRC="$src_hash" MIG_RES="$res_digest" yq -i '
    (.run_units[] | select(.run_unit_id == strenv(MIG_ID)) | .parallel.status) = "safe"
    | (.run_units[] | select(.run_unit_id == strenv(MIG_ID)) | .parallel.provenance.evidence_ref) = strenv(MIG_REF)
    | (.run_units[] | select(.run_unit_id == strenv(MIG_ID)) | .parallel.provenance.verified_at) = strenv(MIG_AT)
    | (.run_units[] | select(.run_unit_id == strenv(MIG_ID)) | .parallel.provenance.method) = "migrated_p071_step3"
    | (.run_units[] | select(.run_unit_id == strenv(MIG_ID)) | .parallel.provenance.source_sha256) = strenv(MIG_SRC)
    | (.run_units[] | select(.run_unit_id == strenv(MIG_ID)) | .parallel.provenance.resource_digest) = strenv(MIG_RES)
  ' "$catalog_path"
  i=$(( i + 1 ))
done

if [[ "${#drifted[@]}" -gt 0 ]]; then
  echo "aid-test-catalog-migrate-p071-allowlist.sh: ${#drifted[@]} listed file(s) have changed since P071 verified them and were NOT migrated." >&2
  echo "  P071's evidence describes content these files no longer have. They stay 'unknown' and run sequentially until re-piloted:" >&2
  printf '    - %s\n' "${drifted[@]}" >&2
fi

echo "aid-test-catalog-migrate-p071-allowlist.sh: migrated $(( ${#unit_ids[@]} - ${#drifted[@]} )) of ${#unit_ids[@]} run units" >&2
