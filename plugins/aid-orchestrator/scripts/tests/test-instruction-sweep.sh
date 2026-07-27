#!/usr/bin/env bash
# test-instruction-sweep.sh — no unqualified per-EPIC release instruction
# survives on an agent-facing surface, and every such surface has a disposition.
# P068 Step 10 (E-068-2_2 Step 4).
#
# Two guards, deliberately separate:
#
#   1. DENYLIST. An obsolete lifecycle instruction is one that tells an agent to
#      release per EPIC WITHOUT saying which mode it applies to. The same
#      sentence is fine when it forks on mode, so the check looks for a mode
#      qualification near the hit rather than banning the words outright — a
#      pure word ban would force the legacy path to become undocumentable.
#
#   2. COMPLETENESS. Every command, skill and agent file must appear in
#      reference/instruction-surface-inventory.md with a disposition. Exit 2
#      when one does not: "not listed" must never read as "fine", because that
#      is exactly how a newly added command ships with stale instructions.
#
# Exit 0 = clean. 1 = a denylist hit. 2 = an undisposed surface.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_ROOT}/../.." && pwd)"
ALLOW="${SCRIPT_DIR}/instruction-sweep-allow.txt"
INVENTORY="${PLUGIN_ROOT}/reference/instruction-surface-inventory.md"

# Allow a fixture tree to be swept instead of the repository, so the check's own
# failure mode can be exercised — a guard never seen to fail is not evidence.
SWEEP_ROOT="${AID_SWEEP_ROOT:-$PLUGIN_ROOT}"

deny_rc=0
inv_rc=0

# ── The obsolete-instruction patterns ───────────────────────────────────────
# Each is a phrase that, unqualified, tells an agent the per-EPIC release is
# simply what happens.
PATTERNS=(
  'per-EPIC release'
  'release + merge to main'
  'Curator + Auditor run in parallel BEFORE merge'
)

# A hit is QUALIFIED when a mode fork appears within 15 lines either side: the
# instruction then says which world it belongs to, which is all this check asks.
QUALIFIERS='legacy_epic_release_mode|plan_branch|mode-dependent|mode-conditional'

_allowed() {
  local file="$1" pattern="$2" line suffix substr
  [[ -f "$ALLOW" ]] || return 1
  while IFS= read -r line; do
    line="${line%%#*}"; line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    suffix="${line%%:*}"; substr="${line#*:}"
    [[ "$file" == *"$suffix" ]] || continue
    [[ "$pattern" == *"$substr"* ]] && return 0
  done < "$ALLOW"
  return 1
}

echo "=== instruction sweep: obsolete lifecycle instructions ==="
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  rel="${f#"$REPO_ROOT"/}"
  for pat in "${PATTERNS[@]}"; do
    while IFS=: read -r lineno _; do
      [[ -n "$lineno" ]] || continue
      _allowed "$rel" "$pat" && continue
      lo=$(( lineno > 15 ? lineno - 15 : 1 ))
      hi=$(( lineno + 15 ))
      if sed -n "${lo},${hi}p" "$f" | grep -qE "$QUALIFIERS"; then
        continue
      fi
      echo "FAIL  ${rel}:${lineno}: unqualified obsolete instruction — '${pat}'" >&2
      echo "      It must fork on mode (${QUALIFIERS//|/, }) or be added to instruction-sweep-allow.txt WITH A REASON." >&2
      deny_rc=1
    done < <(grep -n -F "$pat" "$f" 2>/dev/null || true)
  done
done < <(find "$SWEEP_ROOT" \( -path '*/commands/*.md' -o -path '*/skills/*.md' -o -path '*/agents/*.md' \) -type f 2>/dev/null)
[[ "$deny_rc" -eq 0 ]] && echo "PASS  no unqualified obsolete lifecycle instruction on any agent-facing surface"

# ── Completeness ────────────────────────────────────────────────────────────
if [[ "${AID_SWEEP_ROOT:-}" == "" ]]; then
  echo "=== instruction sweep: inventory completeness ==="
  if [[ ! -f "$INVENTORY" ]]; then
    echo "FAIL  the surface inventory is missing at ${INVENTORY#"$REPO_ROOT"/}" >&2
    inv_rc=2
  else
    while IFS= read -r f; do
      base="$(basename "$f")"
      dir="$(basename "$(dirname "$f")")"
      if ! grep -qF "${dir}/${base}" "$INVENTORY"; then
        echo "FAIL  ${dir}/${base} has no disposition in the surface inventory" >&2
        echo "      Add it as update / verified / no-scope. 'Not listed' must never read as 'fine'." >&2
        inv_rc=2
      fi
    done < <(find "$PLUGIN_ROOT/commands" "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/agents" -maxdepth 1 -name '*.md' -type f 2>/dev/null)
    [[ "$inv_rc" -eq 0 ]] && echo "PASS  every command, skill and agent surface carries a disposition"
  fi
fi

echo "---"
if [[ "$deny_rc" -ne 0 ]]; then echo "test-instruction-sweep: denylist failure" >&2; exit 1; fi
if [[ "$inv_rc" -ne 0 ]]; then echo "test-instruction-sweep: undisposed surface" >&2; exit 2; fi
echo "test-instruction-sweep: OK"
exit 0
