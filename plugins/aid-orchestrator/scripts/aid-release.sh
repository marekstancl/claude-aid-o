#!/usr/bin/env bash
# aid-release.sh — Deterministic version bumping with config-driven file registry
# Usage:
#   aid-release.sh auto [--dry-run] [--force]   # auto-detect bump from conventional commits
#   aid-release.sh <patch|minor|major> [--dry-run] [--force]  # explicit bump
#   aid-release.sh prepare-plan <plan_id> --bump <auto|patch|minor|major>
#                  --plan-branch <branch> [--project-root <path>] [--dry-run]
#
# ── SUBCOMMAND DISPATCH (P068 Step 1) ──────────────────────────────────────
# This script had NO main() and NO dispatch: `BUMP_TYPE="${1:?...}"` was read
# at the top and the whole body ran unconditionally at source time. Adding a
# second entry point therefore meant a RESTRUCTURE, not an insertion: the
# original body is now split into functions and the LEGACY entry point
# (`auto|patch|minor|major`) is preserved EXACTLY — same argument parsing,
# same order of operations, same messages, same `git add -u` + commit + tag.
# Anything that is not the literal token `prepare-plan` in $1 goes down the
# legacy path, including no arguments at all (which still hits the same
# `${1:?Usage: ...}` error).
#
# ── WHY prepare-plan EXISTS ────────────────────────────────────────────────
# The plan-final boundary freezes ONE immutable candidate commit and reviews
# it. The version metadata must therefore already be IN that candidate —
# nothing may be committed after the reviews start. `prepare-plan` applies the
# version-file edits and the CHANGELOG entry, commits them on the plan branch,
# and stops: NO tag, NO push. Tagging happens once, later, at merge time.
#
# It also fixes a staging defect that only matters for a frozen candidate. The
# legacy path stages `git add "${UPDATED[@]}"` and then an UNQUALIFIED
# `git add -u`, which sweeps in every modified tracked file in the worktree.
# For a per-EPIC release that is merely untidy; for a candidate that is about
# to be sealed, hashed and reviewed it is a correctness defect — unrelated
# dirt would silently become part of the reviewed and tagged commit.
# `prepare-plan` refuses to run on a dirty tree and stages ONLY the explicit
# version-file list, so the prepare commit contains exactly the version edits.
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

# ─── Shared stage 1: argument parsing + bump-type resolution ─────────────
# Byte-for-byte the original top-of-script block, wrapped in a function. The
# `${1:?...}` still fires identically when the script is called with no
# arguments, because the legacy dispatch arm forwards "$@" unchanged.
_release_parse_args_and_resolve_bump() {
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
}

# ─── Shared stage 2: Layer 2 FSM state check ─────────────────────────────
# Legacy-only. `prepare-plan` deliberately does NOT run this: it guards the
# per-EPIC FSM (aid-fsm.sh's run states), which is exactly the machinery a
# plan-branch plan structurally skips. The plan-final runner enforces its own,
# stricter precondition instead (plan_state == PLAN_SYNC, clean tree).
_release_fsm_guard() {
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
}

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

_release_detect_version() {
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
}

# ─── Update version files ───────────────────────────────────────────────

_release_update_files() {
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
}

# ─── Git commit + tag (LEGACY path only) ─────────────────────────────────

_release_commit_and_tag() {
cd "$REPO_ROOT"
git add "${UPDATED[@]}" 2>/dev/null || true
# Also add any files updated in the config loop (may have been missed)
git add -u

LAST_FEAT=$(git log --oneline "${LAST_TAG:-HEAD~1}..HEAD" --no-merges --grep="^feat" | head -1 | sed 's/^[a-f0-9]* //' || echo "$BUMP_TYPE bump")
git commit -m "release: v${NEW_VERSION} — ${LAST_FEAT}"
git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"

echo ""
echo "Released v${NEW_VERSION}. Push with: git push --no-verify && git push --tags"
}

# =============================================================================
# LEGACY ENTRY POINT — aid-release.sh <auto|patch|minor|major> [--dry-run] [--force]
#
# The original script, unchanged in behaviour: resolve bump → FSM guard →
# detect version → dry-run exit → update files → commit + tag.
# =============================================================================
_release_legacy_bump() {
  _release_parse_args_and_resolve_bump "$@"
  _release_fsm_guard
  _release_detect_version

  if $DRY_RUN; then
    echo "[DRY RUN] Would update version to $NEW_VERSION"
    exit 0
  fi

  _release_update_files
  _release_commit_and_tag
}

# =============================================================================
# cmd_prepare_plan <plan_id> --bump <auto|patch|minor|major>
#                  --plan-branch <branch> [--project-root <path>] [--dry-run]
#
# The plan-final version-preparation step. Applies the version-file edits and
# the CHANGELOG entry driven by .aid-o/config/project.yaml `versioning.files[]`
# (the same registry the legacy path uses — one implementation, not a fork),
# commits them on the plan branch as
#     release: prepare v<version> for <plan_id>
# and exits WITHOUT tagging or pushing.
#
# ORDER: this runs while the plan is still in PLAN_SYNC — BEFORE the candidate
# is frozen — so it never requires a `candidate_sha` that does not exist yet,
# and the candidate that IS frozen afterwards already contains the release
# metadata.
#
# THREE guarantees the legacy path does not give:
#   1. Clean tree required UP FRONT. Refuses rather than sweeping unrelated
#      modifications into a commit that is about to be frozen and reviewed.
#   2. Explicit staging only. `git add` receives exactly the files this run
#      reports as updated — never `git add -u`. After staging, the staged set
#      is re-read from Git and any file outside the updated list aborts the
#      commit, so the guarantee is checked, not merely intended.
#   3. Idempotent under crash-resume. If HEAD is already a prepare commit for
#      this plan, the existing commit is REUSED (no-op, exit 0) rather than
#      bumping a second time — the version files already carry the new version,
#      so a naive re-run would bump 2.62.2 → 2.62.3.
#
# Exit codes: 0 success or documented no-op (no bump needed / already
# prepared / dry run), 1 precondition failure, 2 usage error.
# =============================================================================
cmd_prepare_plan() {
  local plan_id="" bump="" plan_branch="" project_root="" dry=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bump)
        [[ $# -ge 2 ]] || { echo "ERROR: prepare-plan: --bump requires a value." >&2; exit 2; }
        bump="$2"; shift 2 ;;
      --plan-branch)
        [[ $# -ge 2 ]] || { echo "ERROR: prepare-plan: --plan-branch requires a value." >&2; exit 2; }
        plan_branch="$2"; shift 2 ;;
      --project-root)
        [[ $# -ge 2 ]] || { echo "ERROR: prepare-plan: --project-root requires a value." >&2; exit 2; }
        project_root="$2"; shift 2 ;;
      --dry-run) dry=true; shift ;;
      --*) echo "ERROR: prepare-plan: unknown flag: $1" >&2; exit 2 ;;
      *)
        if [[ -z "$plan_id" ]]; then plan_id="$1"
        else echo "ERROR: prepare-plan: unexpected argument: $1" >&2; exit 2; fi
        shift ;;
    esac
  done

  if [[ -z "$plan_id" || -z "$bump" || -z "$plan_branch" ]]; then
    echo "Usage: aid-release.sh prepare-plan <plan_id> --bump <auto|patch|minor|major> --plan-branch <branch> [--project-root <path>] [--dry-run]" >&2
    exit 2
  fi
  if ! [[ "$plan_id" =~ ^P[0-9]{3}$ ]]; then
    echo "ERROR: prepare-plan: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')" >&2
    exit 2
  fi
  case "$bump" in
    auto|patch|minor|major) ;;
    *) echo "ERROR: prepare-plan: --bump must be auto|patch|minor|major (got '${bump}')" >&2; exit 2 ;;
  esac

  # Re-resolve REPO_ROOT against --project-root when given (the top-level
  # resolution walked up from the invoking CWD, which a runner may not share).
  if [[ -n "$project_root" ]]; then
    REPO_ROOT="$(cd "$project_root" && git rev-parse --show-toplevel 2>/dev/null)" \
      || { echo "PRECONDITION FAIL: prepare-plan: --project-root '${project_root}' is not inside a git repository." >&2; exit 1; }
  fi
  cd "$REPO_ROOT"

  # ── Must be ON the plan branch. Deliberately a refusal, not a checkout:
  #    silently moving HEAD under a runner that is mid-sequence is exactly the
  #    kind of hidden side effect a frozen candidate must not depend on.
  local head_branch=""
  head_branch="$(git -C "$REPO_ROOT" symbolic-ref --short -q HEAD 2>/dev/null)" || head_branch=""
  if [[ "$head_branch" != "$plan_branch" ]]; then
    echo "PRECONDITION FAIL: prepare-plan must run on ${plan_branch}, but HEAD is on '${head_branch:-<detached>}' — check out the plan branch first; this command will not move HEAD for you." >&2
    exit 1
  fi

  # ── Crash-resume convergence: HEAD is already this plan's prepare commit ──
  local head_subject=""
  head_subject="$(git -C "$REPO_ROOT" log -1 --format=%s 2>/dev/null)" || head_subject=""
  if [[ "$head_subject" =~ ^release:\ prepare\ v([0-9]+\.[0-9]+\.[0-9]+)\ for\ ${plan_id}$ ]]; then
    echo "Already prepared: ${head_subject} (HEAD $(git -C "$REPO_ROOT" rev-parse --short HEAD)) — reusing the existing commit, no second bump." >&2
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  # ── Clean tree required BEFORE any edit (guarantee 1). Same exclusion list
  #    as aid-plan-fsm.sh's own preflight: gitignored/runtime paths that are
  #    "dirty" by design are not real blockers.
  local dirty
  dirty="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no \
    | grep -vE '^.. \.aid-o/config/queue\.yaml$|^.. \.aid-o/work/audit-log\.jsonl$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml\.lock$|^.. \.aid-o/work/plan-state/' || true)"
  if [[ -n "$dirty" ]]; then
    echo "PRECONDITION FAIL: prepare-plan refuses to run with modified tracked files — they would be swept into the commit that is about to become the frozen, reviewed candidate. Commit or stash first:" >&2
    printf '%s\n' "$dirty" >&2
    exit 1
  fi

  # ── The shared version machinery (one implementation with the legacy path).
  #    `auto` resolving to "no bump" exits 0 from inside here, before any file
  #    is touched — a chore/docs-only plan legitimately makes no commit and the
  #    candidate is simply the current plan head.
  _release_parse_args_and_resolve_bump "$bump"
  _release_detect_version

  if $dry; then
    echo "[DRY RUN] Would prepare v${NEW_VERSION} for ${plan_id} on ${plan_branch} (no commit, no tag)"
    return 0
  fi

  _release_update_files

  # ── Explicit staging only (guarantee 2) ─────────────────────────────────
  if [[ ${#UPDATED[@]} -eq 0 ]]; then
    echo "PRECONDITION FAIL: prepare-plan resolved a ${BUMP_TYPE} bump to v${NEW_VERSION} but updated no files — refusing to make an empty prepare commit." >&2
    exit 1
  fi

  local f
  for f in "${UPDATED[@]}"; do
    [[ -n "$f" ]] || continue
    git -C "$REPO_ROOT" add -- "$f" \
      || { echo "PRECONDITION FAIL: cannot stage ${f}" >&2; exit 1; }
  done

  # Re-read what is ACTUALLY staged and prove it is a subset of the intended
  # list. A version-file edit that failed partway (guarantee: Error Handling)
  # leaves the tree dirty and this command exits non-zero — no candidate is
  # frozen afterwards because --stage freeze refuses a dirty tree.
  local staged unexpected=""
  staged="$(git -C "$REPO_ROOT" diff --cached --name-only)"
  local want="" rel
  for f in "${UPDATED[@]}"; do
    [[ -n "$f" ]] || continue
    rel="$(realpath -m --relative-to="$REPO_ROOT" -- "$f" 2>/dev/null)" || rel="$f"
    want+="${rel}"$'\n'
  done
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    grep -qxF "$rel" <<<"$want" || unexpected+="${rel}"$'\n'
  done <<<"$staged"
  if [[ -n "$unexpected" ]]; then
    echo "PRECONDITION FAIL: files outside the version-file registry are staged — refusing to fold them into the prepare commit:" >&2
    printf '%s' "$unexpected" >&2
    exit 1
  fi
  if [[ -z "$staged" ]]; then
    echo "PRECONDITION FAIL: nothing staged after the version-file edits — refusing to make an empty prepare commit." >&2
    exit 1
  fi

  git -C "$REPO_ROOT" commit -q -m "release: prepare v${NEW_VERSION} for ${plan_id}" \
    || { echo "PRECONDITION FAIL: prepare commit failed — the version edits remain staged." >&2; exit 1; }

  echo "Prepared v${NEW_VERSION} for ${plan_id} on ${plan_branch} at $(git -C "$REPO_ROOT" rev-parse --short HEAD) — no tag, no push." >&2
  echo "$NEW_VERSION"
  return 0
}

# =============================================================================
# Dispatch. Anything that is not the literal `prepare-plan` goes to the legacy
# entry point with its arguments untouched — including the empty argument list.
# =============================================================================
main() {
  case "${1:-}" in
    prepare-plan) shift; cmd_prepare_plan "$@" ;;
    *) _release_legacy_bump "$@" ;;
  esac
}

main "$@"
