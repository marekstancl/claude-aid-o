#!/usr/bin/env bash
# aid-lint-skill.sh — mechanical conformance linter for AID skill + command files.
#
# Enforces ONLY the unambiguous mechanical subset of skills/skill-writing.md and
# skills/command-writing.md. Judgment checks (accuracy-to-code, the 4-part
# contract, cross-skill duplication, length-band classification, whether a
# "(planned)" note has a real tracking id) are NOT done here — a script cannot
# verify them without false positives. They stay in each standard's manual
# Completeness Gate.
#
# Fenced code blocks (``` … ```) are excluded from heading checks: the standards
# themselves quote the forbidden patterns inside example fences.
#
# Output: one pipe-delimited line per violation, to stdout:
#     LINT|<severity>|<rule>|<file>|<detail>
#   severity = universal  (applies to files of ALL ages — never grandfathered)
#            = structural (grandfathered: advisory for pre-existing files, blocking for new)
#
# Exit: 0 = clean, 1 = one or more violations, 2 = usage/IO error.
# The test harness (test-skill-lint.sh) applies the grandfather allowlist and
# decides what blocks the build; this script only reports.
#
# Usage: aid-lint-skill.sh <file.md>
set -euo pipefail

file="${1:?usage: aid-lint-skill.sh <file.md>}"
[[ -f "$file" ]] || { echo "ERROR: file not found: $file" >&2; exit 2; }

violations=0
emit() { printf 'LINT|%s|%s|%s|%s\n' "$1" "$2" "$file" "$3"; violations=$((violations+1)); }

case "$file" in
  *commands/*) ftype=command ;;
  *)           ftype=skill ;;
esac

# Body with fenced code blocks blanked out (keeps line numbers stable via awk NR).
# Lines inside ``` … ``` fences become empty so example anti-patterns don't match.
fenced_stripped() {
  awk '
    /^[[:space:]]*```/ { infence = !infence; print ""; next }
    { if (infence) print ""; else print }
  ' "$file"
}

# ─── Common: version-stamped headings (Forbidden Pattern) — grandfathered ──
# Only real headings outside code fences. e.g. "## Tiered Severity (v2.21.0)".
while IFS=: read -r lineno text; do
  [[ -z "$lineno" ]] && continue
  emit structural version_stamped_heading "${lineno}:${text}"
done < <(fenced_stripped | grep -nE '^#{2,5} .*(v[0-9]+\.[0-9]+|P0[0-9][0-9]| \(NEW|NEW v[0-9])' 2>/dev/null || true)

# ─── Date helpers ──────────────────────────────────────────────────────────
hdr_date=$(sed -n '1,15p' "$file" | grep -oE '^\*\*Last Updated:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
foot_date=$(grep -oE '^\*\*Last Updated:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}' "$file" | tail -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)

if [[ "$ftype" == skill ]]; then
  fm=$(sed -n '1,8p' "$file")
  grep -qE '^name:' <<<"$fm"          || emit structural frontmatter_missing_name "no name: in frontmatter"
  grep -qE '^description:' <<<"$fm"    || emit structural frontmatter_missing_description "no description: in frontmatter"
  grep -qE '^user_invocable:' <<<"$fm" || emit structural frontmatter_missing_user_invocable "no user_invocable: in frontmatter"

  [[ -n "$hdr_date" ]] || emit structural missing_header_last_updated "no **Last Updated:** in top 15 lines"
  [[ -n "$foot_date" ]] || emit structural missing_footer_last_updated "no **Last Updated:** footer"
  if [[ -n "$hdr_date" && -n "$foot_date" && "$hdr_date" != "$foot_date" ]]; then
    emit structural last_updated_date_mismatch "header=$hdr_date footer=$foot_date"
  fi

elif [[ "$ftype" == command ]]; then
  grep -qE '^description:' <(sed -n '1,6p' "$file") || emit structural frontmatter_missing_description "no description: in frontmatter"
  [[ -n "$foot_date" ]] || emit structural missing_footer_last_updated "no **Last Updated:** footer"

  # Cardinal Rule (accuracy-to-code) — applies to ALL command ages (universal).
  # Bare `state.yaml` presented as CANONICAL is wrong; canonical is fsm-state.yaml
  # (auto-mode-state.yaml is a separate legit file). A line that explicitly labels it
  # legacy/fallback/old/deprecated is CORRECT (acknowledging the old name) and is skipped.
  # Match outside code fences, not preceded by a word char or hyphen.
  while IFS=: read -r lineno text; do
    [[ -z "$lineno" ]] && continue
    printf '%s' "$text" | grep -qiE 'legacy|fallback|deprecat|former|old name|renamed|backward.?compat' && continue
    emit universal legacy_state_yaml_name "${lineno}:${text}"
  done < <(fenced_stripped | grep -nE '(^|[^A-Za-z0-9_-])state\.yaml' 2>/dev/null || true)
fi

[[ "$violations" -eq 0 ]] && exit 0 || exit 1
