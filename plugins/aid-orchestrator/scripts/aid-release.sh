#!/usr/bin/env bash
# aid-release.sh — Version bumping, changelog, git tag
# Usage: aid-release.sh <patch|minor|major> [--dry-run] [--evidence-dir <path>] [--skip-evidence-check]
#
# When --evidence-dir is provided, verifies that Curator and Auditor reports
# exist before allowing release. This enforces the DONE state workflow.

set -euo pipefail

BUMP_TYPE="${1:?Usage: aid-release.sh <patch|minor|major> [--dry-run] [--evidence-dir <path>]}"
DRY_RUN=false
EVIDENCE_DIR=""
SKIP_EVIDENCE=false

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    --skip-evidence-check) SKIP_EVIDENCE=true; shift ;;
    *) shift ;;
  esac
done

# ─── Evidence Check (DONE state enforcement) ─────────────────────────
if [[ -n "$EVIDENCE_DIR" && "$SKIP_EVIDENCE" != "true" ]]; then
  echo "Checking DONE state evidence in: $EVIDENCE_DIR" >&2
  errors=0

  # Curator report must exist
  if [[ ! -f "${EVIDENCE_DIR}/curator-report.yaml" && ! -f "${EVIDENCE_DIR}/curator-report.md" ]]; then
    echo "EVIDENCE FAIL: Curator report not found in ${EVIDENCE_DIR}/. Curator agent must run before release." >&2
    errors=$((errors + 1))
  fi

  # Auditor report must exist
  if [[ ! -f "${EVIDENCE_DIR}/audit-report.yaml" && ! -f "${EVIDENCE_DIR}/audit-report.md" ]]; then
    echo "EVIDENCE FAIL: Auditor report not found in ${EVIDENCE_DIR}/. Auditor agent must run before release." >&2
    errors=$((errors + 1))
  fi

  # Gates report must exist
  if [[ ! -f "${EVIDENCE_DIR}/gates/gates_report.json" ]]; then
    echo "EVIDENCE FAIL: gates_report.json not found in ${EVIDENCE_DIR}/gates/. Gates must pass before release." >&2
    errors=$((errors + 1))
  fi

  if [[ $errors -gt 0 ]]; then
    echo "ERROR: ${errors} evidence check(s) failed. Release blocked." >&2
    echo "Use --skip-evidence-check to bypass (PM-only, will be logged)." >&2
    exit 1
  fi

  echo "Evidence checks passed (curator, auditor, gates)." >&2
fi

# Validate bump type
case "$BUMP_TYPE" in
  patch|minor|major) ;;
  *) echo "ERROR: bump type must be patch|minor|major" >&2; exit 1 ;;
esac

# Read current version from root package.json
[[ -f "package.json" ]] || { echo "ERROR: package.json not found in current directory" >&2; exit 1; }
CURRENT=$(jq -r .version package.json)
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP_TYPE" in
  patch) NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
  minor) NEW_VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
  major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
esac

echo "Bumping: $CURRENT → $NEW_VERSION"

if $DRY_RUN; then
  echo "[DRY RUN] Would update version to $NEW_VERSION in all locations"
  exit 0
fi

# Update version in all locations
VERSION_FILES=(
  "package.json"
  "packages/aid-gui/package.json"
  "packages/aid-server/package.json"
  "plugins/aid-orchestrator/.claude-plugin/plugin.json"
)
for f in "${VERSION_FILES[@]}"; do
  [[ -f "$f" ]] || { echo "WARNING: $f not found, skipping" >&2; continue; }
  tmp=$(mktemp)
  jq ".version = \"$NEW_VERSION\"" "$f" > "$tmp" && mv "$tmp" "$f"
  echo "Updated: $f"
done

# Update CHANGELOG.md (prepend new version section after header line)
CHANGELOG="CHANGELOG.md"
if [[ -f "$CHANGELOG" ]]; then
  TODAY=$(date +%Y-%m-%d)
  CHANGELOG_ENTRY="## [$NEW_VERSION] — $TODAY\n\n### Changed\n- Release $NEW_VERSION\n\n"
  # Insert after the first line (# Changelog header)
  sed -i "2s/^/$CHANGELOG_ENTRY/" "$CHANGELOG"
  echo "Updated: $CHANGELOG"
fi

# Git commit + tag
STAGED_FILES=()
for f in "${VERSION_FILES[@]}"; do
  [[ -f "$f" ]] && STAGED_FILES+=("$f")
done
[[ -f "$CHANGELOG" ]] && STAGED_FILES+=("$CHANGELOG")

git add "${STAGED_FILES[@]}"
git commit -m "chore: release v${NEW_VERSION}"
git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"

echo "Released v${NEW_VERSION}. Push with: git push && git push --tags"
