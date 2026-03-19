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
  STATE_FILE=$(find "$REPO_ROOT/.aid-o/work/runs/" -name "state.yaml" 2>/dev/null | head -1)
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

VERSION_SOURCE=""
CURRENT=""

# Priority: CHANGELOG.md > package.json > pyproject.toml
if [[ -f "$REPO_ROOT/CHANGELOG.md" ]]; then
  CURRENT=$(grep -oP '## \[\K[0-9]+\.[0-9]+\.[0-9]+' "$REPO_ROOT/CHANGELOG.md" | head -1)
  [[ -n "$CURRENT" ]] && VERSION_SOURCE="CHANGELOG.md"
fi

if [[ -z "$CURRENT" && -f "$REPO_ROOT/package.json" ]]; then
  CURRENT=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/package.json')).get('version',''))" 2>/dev/null || true)
  [[ -n "$CURRENT" ]] && VERSION_SOURCE="package.json"
fi

if [[ -z "$CURRENT" && -f "$REPO_ROOT/pyproject.toml" ]]; then
  CURRENT=$(grep -oP '^version\s*=\s*"\K[0-9]+\.[0-9]+\.[0-9]+' "$REPO_ROOT/pyproject.toml" | head -1)
  [[ -n "$CURRENT" ]] && VERSION_SOURCE="pyproject.toml"
fi

if [[ -z "$CURRENT" ]]; then
  echo "ERROR: Cannot detect version. Need CHANGELOG.md (## [X.Y.Z]), package.json, or pyproject.toml." >&2
  exit 1
fi

echo "Version source: $VERSION_SOURCE ($CURRENT)"

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

# Always update source
case "$VERSION_SOURCE" in
  CHANGELOG.md)
    sed -i "s/## \[$CURRENT\].*/## [$NEW_VERSION] — $TODAY/" "$REPO_ROOT/CHANGELOG.md"
    UPDATED+=("$REPO_ROOT/CHANGELOG.md")
    ;;
  package.json)
    tmp=$(mktemp)
    jq ".version = \"$NEW_VERSION\"" "$REPO_ROOT/package.json" > "$tmp" && mv "$tmp" "$REPO_ROOT/package.json"
    UPDATED+=("$REPO_ROOT/package.json")
    ;;
  pyproject.toml)
    sed -i "s/^version = \"$CURRENT\"/version = \"$NEW_VERSION\"/" "$REPO_ROOT/pyproject.toml"
    UPDATED+=("$REPO_ROOT/pyproject.toml")
    ;;
esac
echo "Updated: $VERSION_SOURCE (source)"

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
        sed -i "s/## \[$CURRENT\].*/## [$NEW_VERSION] — $TODAY/" "$FULL_PATH"
        echo "Updated: $FILE_PATH (changelog header)"
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
