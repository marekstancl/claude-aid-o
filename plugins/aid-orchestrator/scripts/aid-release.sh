#!/usr/bin/env bash
# aid-release.sh — Version bumping, changelog, git tag
# Usage: aid-release.sh <patch|minor|major> [--dry-run] [--force]
#
# NOTE: Updates JSON version files only (4 of 8 version registry locations).
# Remaining locations (CHANGELOGs, READMEs) must be updated manually.
# See CLAUDE.md "Version File Registry" for the full 8-location list.

set -euo pipefail

BUMP_TYPE="${1:?Usage: aid-release.sh <patch|minor|major> [--dry-run] [--force]}"
DRY_RUN=false
FORCE=false
for arg in "${@:2}"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
  esac
done

# Validate bump type
case "$BUMP_TYPE" in
  patch|minor|major) ;;
  *) echo "ERROR: bump type must be patch|minor|major" >&2; exit 1 ;;
esac

# Layer 2: FSM state check (soft — only when state.yaml exists)
# Correlate with current branch to find the right state.yaml
STATE_FILE=""
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || true)
BRANCH_ID=$(echo "$CURRENT_BRANCH" | cut -d'/' -f2)

if [[ -d ".aid-o/work/runs/" ]]; then
  while IFS= read -r _f; do
    if [[ -n "$BRANCH_ID" ]] && grep -q "epic_id: ${BRANCH_ID}" "$_f" 2>/dev/null; then
      STATE_FILE="$_f"
      break
    fi
  done < <(find .aid-o/work/runs/ -name "state.yaml" 2>/dev/null)
  # Fallback: if no branch match, take first (backward compat)
  [[ -z "$STATE_FILE" ]] && STATE_FILE=$(find .aid-o/work/runs/ -name "state.yaml" 2>/dev/null | head -1)
fi

if [[ -n "$STATE_FILE" ]]; then
  FSM_STATE=$(grep '^state:' "$STATE_FILE" | awk '{print $2}' || true)
  DONE_PHASE=$(grep '^done_phase:' "$STATE_FILE" | awk '{print $2}' || true)

  if [[ "$FORCE" == "true" ]]; then
    echo "WARNING: --force used, skipping FSM state check (state=${FSM_STATE}, done_phase=${DONE_PHASE:-N/A})" >&2
  elif [[ "$FSM_STATE" == "DONE" && "$DONE_PHASE" != "release" ]]; then
    echo "ERROR: FSM state is DONE but done_phase=${DONE_PHASE:-<not set>}." >&2
    echo "Run Curator + Auditor first, then: aid-fsm.sh done-advance review release" >&2
    echo "Or use --force to bypass (PM only)." >&2
    exit 1
  elif [[ "$FSM_STATE" =~ ^(READY|EXECUTE|GATES|ESCALATION)$ ]]; then
    echo "ERROR: FSM state is ${FSM_STATE} — run is still in progress." >&2
    echo "Complete the run before releasing. Or use --force to bypass (PM only)." >&2
    exit 1
  fi
fi

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
