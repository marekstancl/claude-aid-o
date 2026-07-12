#!/usr/bin/env bash
# verify-version-files.sh — AC16's dedicated checker (P063 Step 4).
#
# Extracted out of the plan's own AC16 (which originally embedded the whole
# check as one long quote-heavy bash one-liner directly in the EPIC markdown)
# into a real script for readability and so the EPIC-generation contract
# parser never has to deal with nested-quote fragments.
#
# Reads all 8 canonical version-file locations from the project root's own
# CLAUDE.md "Version File Registry" table, asserts they all agree on ONE
# version number, asserts that version differs from the pre-EPIC baseline,
# and asserts both CHANGELOG.md files actually mention it (a real entry, not
# just a bump with no changelog trace).
#
# Usage:
#   verify-version-files.sh <new_version> [--project-root <path>] [--baseline <old_version>]
#
#   <new_version>       the version every one of the 8 locations must show,
#                       e.g. 2.56.0
#   --project-root      project root (default: cwd). Same resolve-then-cd
#                        idiom as aid-plan-close-check.sh / aid-gate-runtime-
#                        report.sh.
#   --baseline          the pre-EPIC version <new_version> must differ from.
#                        Optional — if omitted, only the "all 8 agree on
#                        <new_version>" and "both CHANGELOGs mention it"
#                        checks run (no baseline-divergence check).
#
# The 8 canonical locations (root CLAUDE.md "Version File Registry"):
#   1. CHANGELOG.md                                          -> `## [X.Y.Z]` header
#   2. plugins/aid-orchestrator/CHANGELOG.md                  -> `## [X.Y.Z]` header
#   3. .claude-plugin/marketplace.json                        -> .metadata.version
#   4. .claude-plugin/marketplace.json                        -> .plugins[0].version
#   5. plugins/aid-orchestrator/.claude-plugin/plugin.json     -> .version
#   6. plugins/aid-orchestrator/README.md                     -> `- **Plugin:** X.Y.Z`
#   7. README.md                                               -> `- **vX.Y.Z** (current)`
#   8. README.md                                               -> `AGPL-3.0-only — see [LICENSE](LICENSE)` (exact line; presence-only check, carries no version number of its own)
#
# Exit code: 0 iff ALL checks pass. Non-zero + a specific FAIL line otherwise
# (never silent).

usage() {
  cat >&2 <<'EOF'
Usage: verify-version-files.sh <new_version> [--project-root <path>] [--baseline <old_version>]

  <new_version>     version every one of the 8 canonical locations must show
  --project-root    project root containing the 8 files (default: cwd)
  --baseline        pre-EPIC version <new_version> must differ from (optional)
EOF
  exit 2
}

NEW_VERSION=""
PROJECT_ROOT="$(pwd)"
BASELINE_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ $# -ge 2 ]] || usage; PROJECT_ROOT="$2"; shift 2 ;;
    --baseline)     [[ $# -ge 2 ]] || usage; BASELINE_VERSION="$2"; shift 2 ;;
    -h|--help)      usage ;;
    -*)             echo "Unknown flag: $1" >&2; usage ;;
    *)
      [[ -z "$NEW_VERSION" ]] || usage
      NEW_VERSION="$1"; shift ;;
  esac
done
[[ -n "$NEW_VERSION" ]] || usage

cd "$PROJECT_ROOT" || { echo "ERROR: cannot cd into --project-root '$PROJECT_ROOT'" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }

FAILS=()
_check_fail() { FAILS+=("FAIL: $1"); }
_check_pass() { echo "PASS: $1"; }

# 1. Root CHANGELOG.md header
if [[ -f "CHANGELOG.md" ]]; then
  root_changelog_version=$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "CHANGELOG.md" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  if [[ "$root_changelog_version" == "$NEW_VERSION" ]]; then
    _check_pass "CHANGELOG.md header == $NEW_VERSION"
  else
    _check_fail "CHANGELOG.md header is '${root_changelog_version:-<none found>}', expected $NEW_VERSION"
  fi
else
  _check_fail "CHANGELOG.md does not exist"
fi

# 2. Plugin CHANGELOG.md header
PLUGIN_CHANGELOG="plugins/aid-orchestrator/CHANGELOG.md"
if [[ -f "$PLUGIN_CHANGELOG" ]]; then
  plugin_changelog_version=$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$PLUGIN_CHANGELOG" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  if [[ "$plugin_changelog_version" == "$NEW_VERSION" ]]; then
    _check_pass "$PLUGIN_CHANGELOG header == $NEW_VERSION"
  else
    _check_fail "$PLUGIN_CHANGELOG header is '${plugin_changelog_version:-<none found>}', expected $NEW_VERSION"
  fi
else
  _check_fail "$PLUGIN_CHANGELOG does not exist"
fi

# 3 & 4. marketplace.json metadata.version + plugins[0].version
MARKETPLACE_JSON=".claude-plugin/marketplace.json"
if [[ -f "$MARKETPLACE_JSON" ]]; then
  metadata_version=$(jq -r '.metadata.version // ""' "$MARKETPLACE_JSON" 2>/dev/null)
  plugins0_version=$(jq -r '.plugins[0].version // ""' "$MARKETPLACE_JSON" 2>/dev/null)
  if [[ "$metadata_version" == "$NEW_VERSION" ]]; then
    _check_pass "$MARKETPLACE_JSON .metadata.version == $NEW_VERSION"
  else
    _check_fail "$MARKETPLACE_JSON .metadata.version is '${metadata_version:-<none>}', expected $NEW_VERSION"
  fi
  if [[ "$plugins0_version" == "$NEW_VERSION" ]]; then
    _check_pass "$MARKETPLACE_JSON .plugins[0].version == $NEW_VERSION"
  else
    _check_fail "$MARKETPLACE_JSON .plugins[0].version is '${plugins0_version:-<none>}', expected $NEW_VERSION"
  fi
else
  _check_fail "$MARKETPLACE_JSON does not exist"
fi

# 5. plugin.json version
PLUGIN_JSON="plugins/aid-orchestrator/.claude-plugin/plugin.json"
if [[ -f "$PLUGIN_JSON" ]]; then
  plugin_json_version=$(jq -r '.version // ""' "$PLUGIN_JSON" 2>/dev/null)
  if [[ "$plugin_json_version" == "$NEW_VERSION" ]]; then
    _check_pass "$PLUGIN_JSON .version == $NEW_VERSION"
  else
    _check_fail "$PLUGIN_JSON .version is '${plugin_json_version:-<none>}', expected $NEW_VERSION"
  fi
else
  _check_fail "$PLUGIN_JSON does not exist"
fi

# 6. plugin README.md "- **Plugin:** X.Y.Z" line
PLUGIN_README="plugins/aid-orchestrator/README.md"
if [[ -f "$PLUGIN_README" ]]; then
  plugin_readme_version=$(grep -m1 -oE '^\- \*\*Plugin:\*\* [0-9]+\.[0-9]+\.[0-9]+' "$PLUGIN_README" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  if [[ "$plugin_readme_version" == "$NEW_VERSION" ]]; then
    _check_pass "$PLUGIN_README '- **Plugin:**' line == $NEW_VERSION"
  else
    _check_fail "$PLUGIN_README '- **Plugin:**' line is '${plugin_readme_version:-<none found>}', expected $NEW_VERSION"
  fi
else
  _check_fail "$PLUGIN_README does not exist"
fi

# 7. root README.md "- **vX.Y.Z** (current)" Roadmap line
ROOT_README="README.md"
if [[ -f "$ROOT_README" ]]; then
  root_readme_version=$(grep -m1 -oE '^\- \*\*v[0-9]+\.[0-9]+\.[0-9]+\*\* \(current\)' "$ROOT_README" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  if [[ "$root_readme_version" == "$NEW_VERSION" ]]; then
    _check_pass "$ROOT_README '(current)' Roadmap line == $NEW_VERSION"
  else
    _check_fail "$ROOT_README '(current)' Roadmap line is '${root_readme_version:-<none found>}', expected $NEW_VERSION"
  fi

  # 8. Exact LICENSE line (presence-only — carries no version number itself).
  if grep -qF 'AGPL-3.0-only — see [LICENSE](LICENSE)' "$ROOT_README"; then
    _check_pass "$ROOT_README carries the exact AGPL-3.0-only LICENSE line"
  else
    _check_fail "$ROOT_README is missing the exact 'AGPL-3.0-only — see [LICENSE](LICENSE)' line"
  fi
else
  _check_fail "$ROOT_README does not exist"
fi

# Baseline-divergence check (optional).
if [[ -n "$BASELINE_VERSION" ]]; then
  if [[ "$NEW_VERSION" == "$BASELINE_VERSION" ]]; then
    _check_fail "new_version ($NEW_VERSION) must differ from the pre-EPIC baseline ($BASELINE_VERSION) but is identical"
  else
    _check_pass "new_version ($NEW_VERSION) differs from the pre-EPIC baseline ($BASELINE_VERSION)"
  fi
fi

# Both CHANGELOGs must contain a real entry for the new version (the header
# check above already covers "the most recent entry IS this version" — this
# is a broader "mentioned somewhere" sanity check kept as an independent,
# differently-implemented assertion rather than reusing the same grep).
if [[ -f "CHANGELOG.md" ]] && grep -qF "[$NEW_VERSION]" "CHANGELOG.md"; then
  _check_pass "CHANGELOG.md mentions [$NEW_VERSION] somewhere"
else
  _check_fail "CHANGELOG.md does not mention [$NEW_VERSION] anywhere"
fi

if [[ -f "$PLUGIN_CHANGELOG" ]] && grep -qF "[$NEW_VERSION]" "$PLUGIN_CHANGELOG"; then
  _check_pass "$PLUGIN_CHANGELOG mentions [$NEW_VERSION] somewhere"
else
  _check_fail "$PLUGIN_CHANGELOG does not mention [$NEW_VERSION] anywhere"
fi

echo "---"
if [[ "${#FAILS[@]}" -eq 0 ]]; then
  echo "OVERALL: PASS — all 8 canonical version-file locations agree on $NEW_VERSION"
  exit 0
else
  printf '%s\n' "${FAILS[@]}"
  echo "OVERALL: FAIL — ${#FAILS[@]} check(s) failed"
  exit 1
fi
