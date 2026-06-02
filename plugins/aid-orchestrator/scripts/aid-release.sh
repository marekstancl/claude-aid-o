#!/usr/bin/env bash
# aid-release.sh — Deterministic version bumping with config-driven file registry
# Usage:
#   aid-release.sh auto [--dry-run] [--force]   # auto-detect bump from conventional commits
#   aid-release.sh <patch|minor|major> [--dry-run] [--force]  # explicit bump
#
# Version source (single source of truth, auto-detected):
#   1. CHANGELOG.md  (## [X.Y.Z])
#   2. package.json  (.version)
#   3. pyproject.toml (version = "X.Y.Z")
#
# Version targets (what gets updated):
#   - Always: the source file itself
#   - If .aid-o/config/project.yaml has `versioning.files[]`: update those
#   - If no config: update only source + any CHANGELOG.md found
#
# Auto-detection rules (conventional commits since last tag):
#   feat: → minor | fix: → patch | feat!/BREAKING CHANGE → major
#   chore:/docs:/refactor:/test: → no bump (exit 0)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find repo root (walk up from CWD, not from script location)
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

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

LAST_TAG=""
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

    HAS_BREAKING=false
    HAS_FEAT=false
    HAS_FIX=false

    while IFS= read -r line; do
      msg="${line#* }"
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
  fi
fi

case "$BUMP_TYPE" in
  patch|minor|major) ;;
  *) echo "ERROR: bump type must be auto|patch|minor|major" >&2; exit 1 ;;
esac

# ─── Layer 2: FSM state check ───────────────────────────────────────────

STATE_FILE=""
if [[ -d "$REPO_ROOT/.aid-o/work/runs/" ]]; then
  STATE_FILE=$(find "$REPO_ROOT/.aid-o/work/runs/" \( -name "fsm-state.yaml" -o -name "state.yaml" \) 2>/dev/null | head -1)
fi
# Also check evidence dirs
if [[ -z "$STATE_FILE" && -d "$REPO_ROOT/.aid-o/work/evidence/" ]]; then
  STATE_FILE=$(find "$REPO_ROOT/.aid-o/work/evidence/" -name "fsm-state.yaml" -exec grep -l "state: EXECUTE\|state: GATES\|state: READY" {} \; 2>/dev/null | head -1)
fi

if [[ -n "$STATE_FILE" && "$FORCE" != "true" ]]; then
  FSM_STATE=$(grep '^state:' "$STATE_FILE" | awk '{print $2}' || true)
  DONE_PHASE=$(grep '^done_phase:' "$STATE_FILE" | awk '{print $2}' || true)

  if [[ "$FSM_STATE" == "DONE" && "$DONE_PHASE" != "release" ]]; then
    echo "ERROR: FSM state is DONE but done_phase=${DONE_PHASE:-<not set>}." >&2
    echo "Or use --force to bypass." >&2
    exit 1
  elif [[ "$FSM_STATE" =~ ^(READY|EXECUTE|GATES|ESCALATION)$ ]]; then
    echo "ERROR: FSM state is ${FSM_STATE} — run still in progress." >&2
    echo "Or use --force to bypass." >&2
    exit 1
  fi
fi

# ─── Detect version source (single source of truth) ─────────────────────
#
# Two-source detection (IMP-093 fix, v2.19.1):
#   - CHANGELOG_HEADER   = newest "## [X.Y.Z]" in CHANGELOG.md (may be a
#                          pre-written entry for the upcoming release)
#   - RELEASED_VERSION   = .version field of plugin.json / marketplace.json
#                          / package.json (= last actually released version)
#
# CURRENT (= the version we bump from) is RELEASED_VERSION when available,
# otherwise CHANGELOG_HEADER. This prevents the 3x-observed bug where a
# pre-written CHANGELOG entry for the upcoming release was treated as the
# current released version and then renamed to the bumped version, silently
# collapsing prior version's history.

VERSION_SOURCE=""
CHANGELOG_HEADER=""
RELEASED_VERSION=""
CURRENT=""

# Read newest CHANGELOG header (if exists)
if [[ -f "$REPO_ROOT/CHANGELOG.md" ]]; then
  CHANGELOG_HEADER=$(grep -oP '## \[\K[0-9]+\.[0-9]+\.[0-9]+' "$REPO_ROOT/CHANGELOG.md" | head -1)
fi

# Read actually released version from JSON sources (preferred over CHANGELOG)
for jf in \
  "$REPO_ROOT/plugins/aid-orchestrator/.claude-plugin/plugin.json" \
  "$REPO_ROOT/.claude-plugin/marketplace.json" \
  "$REPO_ROOT/package.json"; do
  [[ -f "$jf" ]] || continue
  if command -v jq &>/dev/null; then
    v=$(jq -r '.version // .metadata.version // empty' "$jf" 2>/dev/null || true)
    if [[ -n "$v" && "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      RELEASED_VERSION="$v"
      VERSION_SOURCE="$(basename "$jf")"
      break
    fi
  fi
done

# Fallback to pyproject.toml if no JSON found
if [[ -z "$RELEASED_VERSION" && -f "$REPO_ROOT/pyproject.toml" ]]; then
  RELEASED_VERSION=$(grep -oP '^version\s*=\s*"\K[0-9]+\.[0-9]+\.[0-9]+' "$REPO_ROOT/pyproject.toml" | head -1)
  [[ -n "$RELEASED_VERSION" ]] && VERSION_SOURCE="pyproject.toml"
fi

# CURRENT (bump from) = RELEASED_VERSION if available, otherwise CHANGELOG_HEADER
if [[ -n "$RELEASED_VERSION" ]]; then
  CURRENT="$RELEASED_VERSION"
elif [[ -n "$CHANGELOG_HEADER" ]]; then
  CURRENT="$CHANGELOG_HEADER"
  VERSION_SOURCE="CHANGELOG.md"
fi

if [[ -z "$CURRENT" ]]; then
  echo "ERROR: Cannot detect version. Need plugin.json/marketplace.json/package.json/pyproject.toml or CHANGELOG.md (## [X.Y.Z])." >&2
  exit 1
fi

echo "Version source: $VERSION_SOURCE ($CURRENT)"
[[ -n "$CHANGELOG_HEADER" && "$CHANGELOG_HEADER" != "$CURRENT" ]] && \
  echo "Note: CHANGELOG header is $CHANGELOG_HEADER (pre-written), released version is $CURRENT — will prepend new entry instead of renaming."

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
case "$BUMP_TYPE" in
  patch) NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
  minor) NEW_VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
  major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
esac

echo "Bumping: $CURRENT → $NEW_VERSION ($BUMP_TYPE)"

if $DRY_RUN; then
  echo "[DRY RUN] Would update version to $NEW_VERSION"
  exit 0
fi

# ─── Update version files ───────────────────────────────────────────────

TODAY=$(date +%Y-%m-%d)
UPDATED=()

# IMP-093 fix: CHANGELOG header logic depends on whether it's pre-written
# for the upcoming release (header == NEW_VERSION) or stale at the previously
# released version (header == CURRENT). Skip rename in either case.

update_changelog() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local header
  header=$(grep -oP '## \[\K[0-9]+\.[0-9]+\.[0-9]+' "$file" | head -1)
  if [[ "$header" == "$NEW_VERSION" ]]; then
    # Pre-written entry for upcoming release — header already correct, no-op.
    echo "Skipped: $file (header already $NEW_VERSION — pre-written entry)"
  elif [[ "$header" == "$CURRENT" ]]; then
    # Stale header at released version — bump to new (existing behavior).
    sed -i "s/## \[$CURRENT\].*/## [$NEW_VERSION] — $TODAY/" "$file"
    echo "Updated: $file (header $CURRENT → $NEW_VERSION)"
  else
    # Different state: prepend a new entry above the current top entry.
    # This handles the case where CHANGELOG has been edited but doesn't match
    # current OR new version (e.g., pre-written for an even newer version).
    local tmp; tmp=$(mktemp)
    {
      head -4 "$file"   # # Changelog header + intro lines
      echo ""
      echo "## [$NEW_VERSION] — $TODAY"
      echo ""
      echo "### Changed"
      echo ""
      echo "- _PM/agent: fill in entry content_"
      echo ""
      tail -n +5 "$file"
    } > "$tmp" && mv "$tmp" "$file"
    echo "Updated: $file (prepended new $NEW_VERSION entry — fill in content)"
  fi
}

case "$VERSION_SOURCE" in
  CHANGELOG.md)
    update_changelog "$REPO_ROOT/CHANGELOG.md"
    UPDATED+=("$REPO_ROOT/CHANGELOG.md")
    ;;
  plugin.json|marketplace.json)
    # Source is JSON — handled by versioning.files[] loop below.
    # Still need to update CHANGELOG.md if it exists.
    if [[ -f "$REPO_ROOT/CHANGELOG.md" ]]; then
      update_changelog "$REPO_ROOT/CHANGELOG.md"
      UPDATED+=("$REPO_ROOT/CHANGELOG.md")
    fi
    ;;
  package.json)
    tmp=$(mktemp)
    jq ".version = \"$NEW_VERSION\"" "$REPO_ROOT/package.json" > "$tmp" && mv "$tmp" "$REPO_ROOT/package.json"
    UPDATED+=("$REPO_ROOT/package.json")
    echo "Updated: $REPO_ROOT/package.json (json: .version)"
    ;;
  pyproject.toml)
    sed -i "s/^version = \"$CURRENT\"/version = \"$NEW_VERSION\"/" "$REPO_ROOT/pyproject.toml"
    UPDATED+=("$REPO_ROOT/pyproject.toml")
    echo "Updated: $REPO_ROOT/pyproject.toml (toml: version)"
    ;;
esac

# Read versioning config from project.yaml if it exists
PROJECT_YAML="$REPO_ROOT/.aid-o/config/project.yaml"
if [[ -f "$PROJECT_YAML" ]] && command -v python3 &>/dev/null; then
  # Parse versioning.files[] from YAML
  python3 -c "
import yaml, json, sys
try:
    d = yaml.safe_load(open('$PROJECT_YAML'))
    files = d.get('versioning', {}).get('files', [])
    for f in files:
        print(json.dumps(f))
except:
    pass
" 2>/dev/null | while IFS= read -r entry; do
    FILE_PATH=$(echo "$entry" | python3 -c "import json,sys; print(json.load(sys.stdin).get('path',''))")
    FILE_TYPE=$(echo "$entry" | python3 -c "import json,sys; print(json.load(sys.stdin).get('type',''))")
    FILE_FIELD=$(echo "$entry" | python3 -c "import json,sys; print(json.load(sys.stdin).get('field','version'))")
    FILE_PATTERN=$(echo "$entry" | python3 -c "import json,sys; print(json.load(sys.stdin).get('pattern',''))")

    FULL_PATH="$REPO_ROOT/$FILE_PATH"
    [[ -f "$FULL_PATH" ]] || { echo "WARNING: $FILE_PATH not found, skipping" >&2; continue; }

    case "$FILE_TYPE" in
      json)
        tmp=$(mktemp)
        jq ".$FILE_FIELD = \"$NEW_VERSION\"" "$FULL_PATH" > "$tmp" && mv "$tmp" "$FULL_PATH"
        echo "Updated: $FILE_PATH (json: .$FILE_FIELD)"
        ;;
      regex)
        SEARCH=$(echo "$FILE_PATTERN" | sed "s/{VERSION}/$CURRENT/g")
        REPLACE=$(echo "$FILE_PATTERN" | sed "s/{VERSION}/$NEW_VERSION/g")
        sed -i "s|$SEARCH|$REPLACE|g" "$FULL_PATH"
        echo "Updated: $FILE_PATH (regex)"
        ;;
      toml)
        sed -i "s/^${FILE_FIELD} = \"$CURRENT\"/${FILE_FIELD} = \"$NEW_VERSION\"/" "$FULL_PATH"
        echo "Updated: $FILE_PATH (toml: $FILE_FIELD)"
        ;;
      changelog)
        # IMP-093 fix: use prepend-aware update_changelog helper instead of
        # blind sed-rename, to preserve pre-written entries.
        update_changelog "$FULL_PATH"
        ;;
    esac
    # Collect for git add (in subshell — use temp file)
    echo "$FULL_PATH" >> /tmp/aid-release-updated-$$
  done

  # Read back updated files from temp
  if [[ -f /tmp/aid-release-updated-$$ ]]; then
    while IFS= read -r f; do
      UPDATED+=("$f")
    done < /tmp/aid-release-updated-$$
    rm -f /tmp/aid-release-updated-$$
  fi
else
  # No config — fallback: find and update common files
  # Additional CHANGELOGs
  for cl in $(find "$REPO_ROOT" -maxdepth 4 -name "CHANGELOG.md" ! -path "*/node_modules/*" 2>/dev/null); do
    [[ "$cl" == "$REPO_ROOT/CHANGELOG.md" ]] && continue
    if grep -q "## \[$CURRENT\]" "$cl" 2>/dev/null; then
      sed -i "s/## \[$CURRENT\].*/## [$NEW_VERSION] — $TODAY/" "$cl"
      UPDATED+=("$cl")
      echo "Updated: $cl (changelog)"
    fi
  done

  # JSON files with .version field
  for jf in $(find "$REPO_ROOT" -maxdepth 4 \( -name "plugin.json" -o -name "marketplace.json" -o -name "package.json" \) ! -path "*/node_modules/*" 2>/dev/null); do
    if jq -e ".version == \"$CURRENT\"" "$jf" &>/dev/null; then
      tmp=$(mktemp)
      jq ".version = \"$NEW_VERSION\"" "$jf" > "$tmp" && mv "$tmp" "$jf"
      UPDATED+=("$jf")
      echo "Updated: $jf (json .version)"
    fi
    # Also check metadata.version (marketplace.json)
    if jq -e ".metadata.version == \"$CURRENT\"" "$jf" &>/dev/null; then
      tmp=$(mktemp)
      jq ".metadata.version = \"$NEW_VERSION\"" "$jf" > "$tmp" && mv "$tmp" "$jf"
      # Don't double-add
      echo "Updated: $jf (json .metadata.version)"
    fi
    # plugins[0].version
    if jq -e ".plugins[0].version == \"$CURRENT\"" "$jf" &>/dev/null; then
      tmp=$(mktemp)
      jq ".plugins[0].version = \"$NEW_VERSION\"" "$jf" > "$tmp" && mv "$tmp" "$jf"
      echo "Updated: $jf (json .plugins[0].version)"
    fi
  done

  # README.md with version pattern
  for readme in $(find "$REPO_ROOT" -maxdepth 3 -name "README.md" ! -path "*/node_modules/*" 2>/dev/null); do
    if grep -q "v$CURRENT" "$readme" 2>/dev/null; then
      sed -i "s/v$CURRENT/v$NEW_VERSION/g" "$readme"
      UPDATED+=("$readme")
      echo "Updated: $readme (readme version refs)"
    fi
    if grep -q "Plugin: $CURRENT" "$readme" 2>/dev/null; then
      sed -i "s/Plugin: $CURRENT/Plugin: $NEW_VERSION/" "$readme"
      echo "Updated: $readme (Plugin: version)"
    fi
  done
fi

echo ""
echo "Updated ${#UPDATED[@]} files total."

# ─── Git commit + tag ────────────────────────────────────────────────────

cd "$REPO_ROOT"
git add "${UPDATED[@]}" 2>/dev/null || true
# Also add any files updated in the config loop (may have been missed)
git add -u

LAST_FEAT=$(git log --oneline "${LAST_TAG:-HEAD~1}..HEAD" --no-merges --grep="^feat" | head -1 | sed 's/^[a-f0-9]* //' || echo "$BUMP_TYPE bump")
git commit -m "release: v${NEW_VERSION} — ${LAST_FEAT}"
git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"

echo ""
echo "Released v${NEW_VERSION}. Push with: git push --no-verify && git push --tags"
