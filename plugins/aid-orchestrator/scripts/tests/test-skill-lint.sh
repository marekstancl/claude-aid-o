#!/usr/bin/env bash
# aid-tier: t2
# test-skill-lint.sh — governance guard for skill-writing.md / command-writing.md.
#
# Runs aid-lint-skill.sh over every skills/*.md and commands/*.md and enforces:
#   - UNIVERSAL violations (e.g. a command presenting legacy state.yaml as canonical)
#     BLOCK for files of any age.
#   - STRUCTURAL violations (missing header date, version-stamped headings, …) BLOCK
#     only for files NOT in the grandfather allowlist. Pre-existing files predate the
#     standard and are advisory until they undergo substantive revision; when one is
#     brought up to standard, remove it from GRANDFATHERED below.
#   - The two standard-bearer skills (skill-writing, command-writing) MUST be fully
#     clean — they are not grandfathered.
#
# This is the enforcement mechanism (out-of-band hard fail) that keeps the two
# authoring standards from being Principle-#1 decoration.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LINT="${PLUGIN_DIR}/scripts/aid-lint-skill.sh"

# Scope note: this gate iterates skills/*.md + commands/*.md ONLY. agents/*.md are
# intentionally OUT of scope — specialist agents (including the P045 additions
# simplifier.md / reporter.md) follow the minimal specialist-agent frontmatter
# convention, parity with curator.md / auditor.md, and carry the same two minimal-
# frontmatter structural findings by design. Linting them here would falsely fail
# the gate, so the new agents are neither grandfathered nor in scope — the gate's
# behavior is unchanged by their addition.
#
# Files that predate the authoring standards — structural findings are advisory for
# these until they are substantively revised (>25%). Universal findings still block.
GRANDFATHERED=$(cat <<'EOF'
skills/agent-protocol.md
skills/memory-mcp.md
skills/memory.md
skills/pipeline.md
skills/planner.md
skills/role-cards.md
skills/run-management.md
commands/aid-audit.md
commands/aid-do.md
commands/aid-plan.md
commands/aid-run.md
commands/aid-status.md
commands/aid-stop.md
EOF
)

is_grandfathered() { grep -qxF "$1" <<<"$GRANDFATHERED"; }

pass=0; fail=0; advisory=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass+1)); }

cd "$PLUGIN_DIR"

echo "TEST: aid-lint-skill.sh exists and is executable"
[[ -x "$LINT" ]] && pass_msg "linter present + executable" || fail_msg "linter missing or not executable: $LINT"

echo "TEST: every skill + command passes the guard (grandfather-aware)"
for f in skills/*.md commands/*.md; do
  out=$(bash "$LINT" "$f" 2>/dev/null || true)
  [[ -z "$out" ]] && continue
  univ=$(grep -c '^LINT|universal|' <<<"$out" || true)
  struct=$(grep -c '^LINT|structural|' <<<"$out" || true)
  if (( univ > 0 )); then
    fail_msg "$f has $univ UNIVERSAL violation(s):"
    grep '^LINT|universal|' <<<"$out" | sed 's/^/      /'
  fi
  if (( struct > 0 )); then
    if is_grandfathered "$f"; then
      advisory=$((advisory+struct))
    else
      fail_msg "$f (NOT grandfathered) has $struct STRUCTURAL violation(s):"
      grep '^LINT|structural|' <<<"$out" | sed 's/^/      /'
    fi
  fi
done
(( fail == 0 )) && pass_msg "no blocking violations (universal on any file; structural on non-grandfathered)"

echo "TEST: standard-bearer skills are fully clean (skill-writing.md, command-writing.md)"
for f in skills/skill-writing.md skills/command-writing.md; do
  if [[ ! -f "$f" ]]; then fail_msg "$f missing"; continue; fi
  out=$(bash "$LINT" "$f" 2>/dev/null || true)
  [[ -z "$out" ]] && pass_msg "$(basename "$f") clean" || { fail_msg "$(basename "$f") must be clean but has violations:"; sed 's/^/      /' <<<"$out"; }
done

echo "TEST: grandfather list contains no stale entries (every listed file still exists)"
stale=0
while IFS= read -r gf; do
  [[ -z "$gf" ]] && continue
  [[ -f "$gf" ]] || { echo "      stale grandfather entry: $gf"; stale=$((stale+1)); }
done <<<"$GRANDFATHERED"
(( stale == 0 )) && pass_msg "grandfather list clean" || fail_msg "$stale stale grandfather entries"

echo "----------------------------------------------------------------------"
total=$(( pass + fail ))
echo "Results: ${pass}/${total} passed, ${fail} failed${advisory:+ (plus ${advisory} advisory grandfathered-structural notes)}"
[[ "$fail" -eq 0 ]]
