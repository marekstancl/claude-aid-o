#!/usr/bin/env bash
# aid-release.sh — Deterministic version bumping across all 8 registry locations
# Usage:
#   aid-release.sh auto [--dry-run] [--force]   # auto-detect bump from conventional commits
#   aid-release.sh <patch|minor|major> [--dry-run] [--force]  # explicit bump
#
# Auto-detection rules (conventional commits since last tag):
#   feat: → minor bump
#   fix:  → patch bump
#   feat!: or BREAKING CHANGE → major bump
#   chore:/docs:/refactor:/test: → no bump needed (exits 0)
#
# Updates ALL 8 version registry locations defined in CLAUDE.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

BUMP_TYPE="${1:?Usage: aid-release.sh <auto|patch|minor|major> [--dry-run] [--force]}"
DRY_RUN=false
FORCE=false
for arg in "${@:2}"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
  esac
done

# ─── Auto-detection from conventional commits ────────────────────────────

if [[ "$BUMP_TYPE" == "auto" ]]; then
  LAST_TAG=$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo "")

  if [[ -z "$LAST_TAG" ]]; then
    echo "No previous tag found — defaulting to patch" >&2
    BUMP_TYPE="patch"
  else
    COMMITS=$(git -C "$REPO_ROOT" log "${LAST_TAG}..HEAD" --oneline --no-merges 2>/dev/null || true)

    if [[ -z "$COMMITS" ]]; then
      echo "No commits since $LAST_TAG — nothing to release." >&2
      exit 0
    fi

    # Detect bump type from commit prefixes
    HAS_BREAKING=false
    HAS_FEAT=false
    HAS_FIX=false

    while IFS= read -r line; do
      msg="${line#* }"  # strip hash
      if [[ "$msg" =~ ^feat!: ]] || [[ "$msg" =~ BREAKING\ CHANGE ]]; then
        HAS_BREAKING=true
      elif [[ "$msg" =~ ^feat ]]; then
        HAS_FEAT=true
      elif [[ "$msg" =~ ^fix ]]; then
        HAS_FIX=true
      fi
    done <<< "$COMMITS"

    if $HAS_BREAKING; then
      BUMP_TYPE="major"
    elif $HAS_FEAT; then
      BUMP_TYPE="minor"
    elif $HAS_FIX; then
      BUMP_TYPE="patch"
    else
      echo "Only chore/docs/refactor/test commits since $LAST_TAG — no version bump needed." >&2
      exit 0
    fi

    COMMIT_COUNT=$(echo "$COMMITS" | wc -l)
    echo "Auto-detected: $BUMP_TYPE (from $COMMIT_COUNT commits since $LAST_TAG)" >&2
    echo "  breaking=$HAS_BREAKING feat=$HAS_FEAT fix=$HAS_FIX" >&2
  fi
fi

# Validate bump type
case "$BUMP_TYPE" in
  patch|minor|major) ;;
  *) echo "ERROR: bump type must be auto|patch|minor|major" >&2; exit 1 ;;
esac

# ─── Layer 2: FSM state check ───────────────────────────────────────────

STATE_FILE=""
CURRENT_BRANCH=$(git -C "$REPO_ROOT" symbolic-ref --short HEAD 2>/dev/null || true)
BRANCH_ID=$(echo "$CURRENT_BRANCH" | cut -d'/' -f2)

if [[ -d "$REPO_ROOT/.aid-o/work/runs/" ]]; then
  while IFS= read -r _f; do
    if [[ -n "$BRANCH_ID" ]] && grep -q "epic_id: ${BRANCH_ID}" "$_f" 2>/dev/null; then
      STATE_FILE="$_f"
      break
    fi
  done < <(find "$REPO_ROOT/.aid-o/work/runs/" -name "state.yaml" 2>/dev/null)
  [[ -z "$STATE_FILE" ]] && STATE_FILE=$(find "$REPO_ROOT/.aid-o/work/runs/" -name "state.yaml" 2>/dev/null | head -1)
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

# ─── Read current version ───────────────────────────────────────────────

# Source of truth: CHANGELOG.md header
CURRENT=$(grep -oP '## \[\K[0-9]+\.[0-9]+\.[0-9]+' "$REPO_ROOT/CHANGELOG.md" | head -1)
if [[ -z "$CURRENT" ]]; then
  echo "ERROR: Cannot read current version from CHANGELOG.md" >&2
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP_TYPE" in
  patch) NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
  minor) NEW_VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
  major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
esac

echo "Bumping: $CURRENT → $NEW_VERSION ($BUMP_TYPE)"

if $DRY_RUN; then
  echo "[DRY RUN] Would update version to $NEW_VERSION in all 8 registry locations"
  exit 0
fi

# ─── Update ALL 8 version registry locations ─────────────────────────────

TODAY=$(date +%Y-%m-%d)
UPDATED=()

# #1 + #2: CHANGELOG.md headers (both root and plugin)
for cl in "$REPO_ROOT/CHANGELOG.md" "$REPO_ROOT/plugins/aid-orchestrator/CHANGELOG.md"; do
  if [[ -f "$cl" ]]; then
    sed -i "s/## \[$CURRENT\]/## [$NEW_VERSION] — $TODAY/" "$cl"
    UPDATED+=("$cl")
    echo "Updated: $cl"
  fi
done

# #3 + #4: marketplace.json (metadata.version + plugins[0].version)
MKT="$REPO_ROOT/.claude-plugin/marketplace.json"
if [[ -f "$MKT" ]]; then
  tmp=$(mktemp)
  jq ".metadata.version = \"$NEW_VERSION\" | .plugins[0].version = \"$NEW_VERSION\"" "$MKT" > "$tmp" && mv "$tmp" "$MKT"
  UPDATED+=("$MKT")
  echo "Updated: $MKT (metadata + plugins[0])"
fi

# #5: plugin.json
PLUGIN_JSON="$REPO_ROOT/plugins/aid-orchestrator/.claude-plugin/plugin.json"
if [[ -f "$PLUGIN_JSON" ]]; then
  tmp=$(mktemp)
  jq ".version = \"$NEW_VERSION\"" "$PLUGIN_JSON" > "$tmp" && mv "$tmp" "$PLUGIN_JSON"
  UPDATED+=("$PLUGIN_JSON")
  echo "Updated: $PLUGIN_JSON"
fi

# #6: plugins/aid-orchestrator/README.md (Plugin: X.Y.Z)
PLUGIN_README="$REPO_ROOT/plugins/aid-orchestrator/README.md"
if [[ -f "$PLUGIN_README" ]]; then
  sed -i "s/Plugin: $CURRENT/Plugin: $NEW_VERSION/" "$PLUGIN_README"
  UPDATED+=("$PLUGIN_README")
  echo "Updated: $PLUGIN_README"
fi

# #7: README.md roadmap (vX.Y.Z (current))
ROOT_README="$REPO_ROOT/README.md"
if [[ -f "$ROOT_README" ]]; then
  sed -i "s/v$CURRENT (current)/v$NEW_VERSION (current)/" "$ROOT_README"
  UPDATED+=("$ROOT_README")
  echo "Updated: $ROOT_README"
fi

# #8: README.md license line — no version, skip

echo ""
echo "Updated ${#UPDATED[@]} files."

# ─── Git commit + tag ────────────────────────────────────────────────────

cd "$REPO_ROOT"
git add "${UPDATED[@]}"
git commit -m "release: v${NEW_VERSION} — $(git log --oneline "${LAST_TAG:-HEAD~1}..HEAD~1" --no-merges | head -1 | sed 's/^[a-f0-9]* //')"
git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"

echo ""
echo "Released v${NEW_VERSION}. Push with: git push && git push --tags"
