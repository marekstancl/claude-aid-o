#!/usr/bin/env bash
# aid-release.sh — Deterministic version bumping with config-driven file registry
# Usage:
#   aid-release.sh auto [--dry-run] [--force]   # auto-detect bump from conventional commits
#   aid-release.sh <patch|minor|major> [--dry-run] [--force]  # explicit bump
#   aid-release.sh prepare-plan <plan_id> --bump <auto|patch|minor|major>
#                  --plan-branch <branch> [--project-root <path>] [--dry-run]
#   aid-release.sh tag-plan <plan_id> --merge-sha <sha> --version <X.Y.Z>
#                  [--project-root <path>]      # P068 Step 5 — the ONE plan tag
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
      # P068 Step 5: a plan-mode caller must be able to distinguish "no bump was
      # needed" from "the bump failed" AFTER this function has exited the whole
      # script. The hook records `version: none` in release-prep.json first, so
      # plan-merge-to-main knows not to call tag-plan. Legacy callers set no hook
      # and see byte-identical behaviour.
      if [[ -n "${_RELEASE_NOBUMP_HOOK:-}" ]]; then "$_RELEASE_NOBUMP_HOOK"; fi
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
      if [[ -n "${_RELEASE_NOBUMP_HOOK:-}" ]]; then "$_RELEASE_NOBUMP_HOOK"; fi
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

# ─── Version-probe primitive (P073 Step 2) ──────────────────────────────
#
# Every "optional" version probe in this script goes through here. Three
# distinct outcomes, none of them silent:
#   - a match      -> _PROBE_RESULT holds the FIRST match, return 0
#   - no match     -> _PROBE_RESULT is empty, return 0 (the caller's own
#                     downstream logic decides what that means)
#   - unreadable / a genuine grep error -> an ERROR naming the file, return 1
#                     (callers `|| exit 1`)
#
# Two things this deliberately does NOT do:
#   - it does not pipe through `head -1`. Closing the pipe early can leave
#     grep killed by SIGPIPE, and under `set -o pipefail` that non-zero
#     status is indistinguishable from "no match" — a `|| VAR=""` fallback
#     would then DISCARD a match that was genuinely found. Measured on this
#     machine: a ~290 KB CHANGELOG reproduces exit 141 on 20/20 runs.
#     `grep -m1` keeps the probe a single process with meaningful exit codes.
#   - it does not blanket-mask the exit status. grep distinguishes 1 (no
#     match) from >=2 (a real error, including a file that became unreadable
#     after the `-r` test), and only the former is treated as "no match".
_PROBE_RESULT=""
_release_probe_first() {
  local file="$1" pattern="$2" out rc
  _PROBE_RESULT=""
  if [[ ! -r "$file" ]]; then
    echo "ERROR: cannot read $file while detecting version" >&2
    return 1
  fi
  out="$(grep -m1 -oP "$pattern" "$file")" && rc=0 || rc=$?
  if [[ "$rc" -ge 2 ]]; then
    echo "ERROR: failed to read $file while detecting version (grep exit $rc)" >&2
    return 1
  fi
  # `-o` can emit more than one match from the single matched line; the
  # callers all want the first.
  _PROBE_RESULT="${out%%$'\n'*}"
  return 0
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

# Read newest CHANGELOG header (if exists).
# P073 Step 2: this script runs under `set -euo pipefail`, so a grep that
# simply finds nothing returned 1 and used to kill the run BEFORE the explicit
# "Cannot detect version" diagnostic below could ever print. See
# _release_probe_first for the three-way outcome this now has.
if [[ -f "$REPO_ROOT/CHANGELOG.md" ]]; then
  _release_probe_first "$REPO_ROOT/CHANGELOG.md" '## \[\K[0-9]+\.[0-9]+\.[0-9]+' || exit 1
  CHANGELOG_HEADER="$_PROBE_RESULT"
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
  # P073 Step 2: a pyproject.toml with no top-level `version = "X.Y.Z"` line
  # (a workspace root, a poetry file using a different key) must FALL THROUGH
  # to the diagnostic below, not abort the script here.
  _release_probe_first "$REPO_ROOT/pyproject.toml" '^version\s*=\s*"\K[0-9]+\.[0-9]+\.[0-9]+' || exit 1
  RELEASED_VERSION="$_PROBE_RESULT"
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
  # P073 Step 2: a CHANGELOG with no version ledger at all (a landing page)
  # must reach the prepend branch below, not abort the release mid-update —
  # and a SIGPIPE-truncated probe must never make a populated CHANGELOG look
  # headerless (which would prepend a duplicate entry).
  local header
  _release_probe_first "$file" '## \[\K[0-9]+\.[0-9]+\.[0-9]+' || exit 1
  header="$_PROBE_RESULT"
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

# ─── CHANGELOG entry validation (P073 Step 3) ───────────────────────────
#
# `update_changelog` writes the literal placeholder below when it PREPENDS a
# new section, and until now nothing ever read it back — a release could be
# committed, tagged and published with "fill in entry content" as its entire
# user-facing description. This is the checker; the two call sites are
# `cmd_prepare_plan` (whose commit becomes the frozen, reviewed candidate —
# the high-value hook) and the legacy `_release_commit_and_tag`.
#
# Blocking conditions, all three about the TARGET version's own section:
#   - the section is absent (including "the file uses a heading format this
#     script cannot locate" — never a silent pass)
#   - the section still contains the exact generated placeholder line
#   - the section has no real bullet at all (e.g. only a `### Changed` heading)
# A placeholder in an OLDER section is historical debt: reported on stderr,
# never blocking.
_RELEASE_CHANGELOG_PLACEHOLDER='- _PM/agent: fill in entry content_'

# _release_changelog_section <file> <version> — prints the target section's
# body (everything between `## [<version>]` and the next `## [` heading).
_release_changelog_section() {
  local file="$1" version="$2"
  awk -v ver="$version" '
    index($0, "## [" ver "]") == 1 { inblock = 1; next }
    inblock && index($0, "## [") == 1 { exit }
    inblock { print }
  ' "$file"
}

# _release_validate_changelog_entry <file> <version> — 0 = entry is real,
# 1 = blocked (message on stderr naming file, version and the required edit).
_release_validate_changelog_entry() {
  local file="$1" version="$2"
  [[ -f "$file" ]] || return 0

  if ! grep -qF "## [${version}]" "$file"; then
    echo "PRECONDITION FAIL: CHANGELOG entry for ${version} in ${file} is incomplete — no '## [${version}]' section was found (this script locates entries by that exact heading form); add the section with a real user-facing description and rerun" >&2
    return 1
  fi

  local block
  block="$(_release_changelog_section "$file" "$version")"

  # `--` is required: the placeholder literal starts with "- ", which grep
  # would otherwise parse as an option.
  if grep -qxF -- "$_RELEASE_CHANGELOG_PLACEHOLDER" <<<"$block"; then
    echo "PRECONDITION FAIL: CHANGELOG entry for ${version} in ${file} is incomplete — replace the placeholder with a real user-facing description and rerun" >&2
    return 1
  fi

  # At least one bullet that is not a placeholder-shaped italic line. The
  # class excludes '_' so the generated placeholder can never satisfy this
  # even if its wording changes, and excludes whitespace so '- ' alone fails.
  if ! grep -qE -- '^- [^_[:space:]]' <<<"$block"; then
    echo "PRECONDITION FAIL: CHANGELOG entry for ${version} in ${file} is incomplete — the section has no content bullet; add a real user-facing description and rerun" >&2
    return 1
  fi

  # Historical placeholders elsewhere in the file: debt, reported once per
  # offending section, never blocking this release.
  local stale
  stale="$(awk -v ver="$version" -v ph="$_RELEASE_CHANGELOG_PLACEHOLDER" '
    index($0, "## [") == 1 { section = $0; intarget = (index($0, "## [" ver "]") == 1); next }
    !intarget && $0 == ph && section != "" && !(section in seen) { seen[section] = 1; print section }
  ' "$file")"
  if [[ -n "$stale" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      echo "WARNING: historical placeholder in section ${line%% —*} of ${file} — debt, not blocking" >&2
    done <<<"$stale"
  fi
  return 0
}

# _release_validate_updated_changelogs <version> — runs the check over every
# CHANGELOG.md in the current UPDATED[] set. Returns 1 if ANY is incomplete.
_release_validate_updated_changelogs() {
  local version="$1" f rc=0
  # Scope: the CHANGELOGs this release actually touched. A CHANGELOG.md that
  # is not part of the version registry is deliberately NOT validated — that
  # would be a new blocking gate on repositories the release path never wrote
  # to, which the plan's loosening directive forbids.
  for f in "${UPDATED[@]:-}"; do
    [[ -n "$f" ]] || continue
    [[ "$(basename "$f")" == "CHANGELOG.md" ]] || continue
    _release_validate_changelog_entry "$f" "$version" || rc=1
  done
  return "$rc"
}

# ─── Git commit + tag (LEGACY path only) ─────────────────────────────────

_release_commit_and_tag() {
cd "$REPO_ROOT"

# P073 Step 3: refuse to commit or tag a release whose own CHANGELOG entry is
# still the generated placeholder. Exits BEFORE the commit, so the edits stay
# in the worktree for correction.
if ! _release_validate_updated_changelogs "$NEW_VERSION"; then
  echo "No release commit and no tag were created — amend the entry and rerun." >&2
  exit 1
fi

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

# ── release-prep.json — the record `plan-merge-to-main` reads to decide whether
#    to tag at all (P068 Step 5) ────────────────────────────────────────────
#
# `prepare-plan --bump auto` may legitimately resolve to NO bump (only chore:/
# docs: commits since the last tag). It then makes no version commit, the
# candidate's version equals the already-released one, and calling
# `tag-plan --version <that version>` would FAIL, because a tag for it already
# exists on an older commit. A no-bump plan merging and closing with no new tag
# is a legal outcome, not a tag-plan failure — so the resolved version, or the
# literal string `none`, is recorded here and plan-merge-to-main calls tag-plan
# only when a new version was actually prepared.
#
# LOCATION: the plan's runtime state directory, because prepare-plan runs BEFORE
# `--stage freeze` and the plan-final run directory does not exist yet.
# `--stage freeze` copies this file into the run directory it allocates, so the
# record also lives with the attempt's evidence; plan-merge-to-main reads the
# run-directory copy first and falls back to this canonical one.
_release_plan_state_dir() {
  local plan_id="$1"
  local common_dir root
  common_dir="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common_dir=""
  if [[ -n "$common_dir" ]]; then root="$(dirname "$common_dir")"; else root="$REPO_ROOT"; fi
  printf '%s/.aid-o/work/plan-state/%s' "$root" "$plan_id"
}

# _release_write_prep_record <plan_id> <plan_branch> <bump> <version|none>
_release_write_prep_record() {
  local plan_id="$1" plan_branch="$2" bump="$3" version="$4"
  local dir; dir="$(_release_plan_state_dir "$plan_id")"
  mkdir -p "$dir" || { echo "PRECONDITION FAIL: cannot create ${dir} for release-prep.json" >&2; return 1; }
  local head=""
  head="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)" || head=""
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg p "$plan_id" --arg b "$plan_branch" --arg bump "$bump" \
        --arg v "$version" --arg h "$head" --arg ts "$ts" \
    '{schema_version:"aid-release-prep-1.0", plan_id:$p, plan_branch:$b,
      bump_requested:$bump, version:$v, prepare_commit:$h, prepared_at:$ts}' \
    > "${dir}/release-prep.json.tmp" \
    && mv "${dir}/release-prep.json.tmp" "${dir}/release-prep.json" \
    || { rm -f "${dir}/release-prep.json.tmp"; echo "PRECONDITION FAIL: could not write ${dir}/release-prep.json" >&2; return 1; }
  return 0
}

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
    # Re-assert the record on the resume path too: a crash between the commit and
    # the record would otherwise leave plan-merge-to-main with no way to know a
    # version WAS prepared, and it would silently skip the one tag.
    $dry || _release_write_prep_record "$plan_id" "$plan_branch" "$bump" "${BASH_REMATCH[1]}" || return 1
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
  # The no-bump hook: `_release_parse_args_and_resolve_bump` exits the whole
  # script when `auto` resolves to no bump, so the `version: none` record has to
  # be written from inside it. A dry run records nothing (it changes nothing).
  if ! $dry; then
    _AID_PREP_PLAN_ID="$plan_id"; _AID_PREP_PLAN_BRANCH="$plan_branch"; _AID_PREP_BUMP="$bump"
    _release_prepare_plan_record_none() {
      _release_write_prep_record "$_AID_PREP_PLAN_ID" "$_AID_PREP_PLAN_BRANCH" "$_AID_PREP_BUMP" "none" || true
    }
    _RELEASE_NOBUMP_HOOK=_release_prepare_plan_record_none
  fi

  _release_parse_args_and_resolve_bump "$bump"
  _release_detect_version

  if $dry; then
    echo "[DRY RUN] Would prepare v${NEW_VERSION} for ${plan_id} on ${plan_branch} (no commit, no tag)"
    return 0
  fi

  _release_update_files

  # P073 Step 3: this commit becomes the frozen, REVIEWED candidate, so a
  # placeholder entry here would be reviewed and released as the release's
  # user-facing description. Exits before any `git add`, leaving the worktree
  # uncommitted for correction — matching the precondition style below.
  if ! _release_validate_updated_changelogs "$NEW_VERSION"; then
    echo "PRECONDITION FAIL: prepare-plan will not freeze a candidate whose CHANGELOG entry is incomplete — nothing was staged or committed." >&2
    exit 1
  fi

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

  _release_write_prep_record "$plan_id" "$plan_branch" "$bump" "$NEW_VERSION" || return 1

  echo "Prepared v${NEW_VERSION} for ${plan_id} on ${plan_branch} at $(git -C "$REPO_ROOT" rev-parse --short HEAD) — no tag, no push." >&2
  echo "$NEW_VERSION"
  return 0
}

# =============================================================================
# cmd_tag_plan <plan_id> --merge-sha <sha> --version <X.Y.Z> [--project-root <p>]
#
# The ONE tag of a plan_branch plan, created on the plan's merge commit on the
# target branch — never per EPIC. Called by `aid-plan-fsm.sh plan-merge-to-main`
# AFTER the merge is published and the lifecycle delivery bindings are written,
# and ONLY when `prepare-plan` actually resolved a version bump (a no-bump plan
# merges and closes with no new tag; see release-prep.json above).
#
# IDEMPOTENT BY CONSTRUCTION — this is the crash-resume contract:
#   - tag absent            -> create it on <merge-sha>, exit 0
#   - tag exists on <merge-sha> -> exit 0, doing nothing (the resumed run of a
#     process that died between the tag and the push finds its own tag)
#   - tag exists ELSEWHERE  -> exit 1, touching nothing. Re-pointing a published
#     tag is never automatic; a released version is immutable.
#
# It NEVER pushes and NEVER moves a branch.
# Exit codes: 0 tagged or already correctly tagged, 1 precondition failure /
# tag collision on another commit, 2 usage error.
# =============================================================================
cmd_tag_plan() {
  local plan_id="" merge_sha="" version="" project_root=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --merge-sha)
        [[ $# -ge 2 ]] || { echo "ERROR: tag-plan: --merge-sha requires a value." >&2; exit 2; }
        merge_sha="$2"; shift 2 ;;
      --version)
        [[ $# -ge 2 ]] || { echo "ERROR: tag-plan: --version requires a value." >&2; exit 2; }
        version="$2"; shift 2 ;;
      --project-root)
        [[ $# -ge 2 ]] || { echo "ERROR: tag-plan: --project-root requires a value." >&2; exit 2; }
        project_root="$2"; shift 2 ;;
      --*) echo "ERROR: tag-plan: unknown flag: $1" >&2; exit 2 ;;
      *)
        if [[ -z "$plan_id" ]]; then plan_id="$1"
        else echo "ERROR: tag-plan: unexpected argument: $1" >&2; exit 2; fi
        shift ;;
    esac
  done

  if [[ -z "$plan_id" || -z "$merge_sha" || -z "$version" ]]; then
    echo "Usage: aid-release.sh tag-plan <plan_id> --merge-sha <sha> --version <X.Y.Z> [--project-root <path>]" >&2
    exit 2
  fi
  if ! [[ "$plan_id" =~ ^P[0-9]{3}$ ]]; then
    echo "ERROR: tag-plan: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')" >&2
    exit 2
  fi
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: tag-plan: --version must be X.Y.Z (got '${version}'). The literal 'none' is not a version — a no-bump plan must not call tag-plan at all." >&2
    exit 2
  fi

  if [[ -n "$project_root" ]]; then
    REPO_ROOT="$(cd "$project_root" && git rev-parse --show-toplevel 2>/dev/null)" \
      || { echo "PRECONDITION FAIL: tag-plan: --project-root '${project_root}' is not inside a git repository." >&2; exit 1; }
  fi

  local target=""
  target="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "${merge_sha}^{commit}" 2>/dev/null)" || target=""
  if [[ -z "$target" ]]; then
    echo "PRECONDITION FAIL: tag-plan: --merge-sha '${merge_sha}' does not resolve to a commit — refusing to tag a SHA that is not in this repository." >&2
    exit 1
  fi

  local tag="v${version}"
  local existing=""
  existing="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/tags/${tag}^{commit}" 2>/dev/null)" || existing=""
  if [[ -n "$existing" ]]; then
    if [[ "$existing" == "$target" ]]; then
      echo "Tag ${tag} already exists on ${target} — nothing to do (idempotent)." >&2
      echo "$tag"
      return 0
    fi
    echo "PRECONDITION FAIL: tag-plan: ${tag} already exists and points at ${existing}, not at the plan merge commit ${target}. A released version is immutable — refusing to move the tag. Resolve by preparing a NEW version for ${plan_id}." >&2
    exit 1
  fi

  git -C "$REPO_ROOT" tag -a "$tag" -m "Release ${tag} (${plan_id})" "$target" \
    || { echo "PRECONDITION FAIL: tag-plan: could not create ${tag} on ${target}." >&2; exit 1; }
  echo "Tagged ${tag} on ${target} for ${plan_id} — no push." >&2
  echo "$tag"
  return 0
}

# =============================================================================
# Dispatch. Anything that is not one of the literal plan-mode subcommands
# (`prepare-plan`, `tag-plan`) goes to the legacy entry point with its arguments
# untouched — including the empty argument list.
# =============================================================================
main() {
  case "${1:-}" in
    prepare-plan) shift; cmd_prepare_plan "$@" ;;
    tag-plan)     shift; cmd_tag_plan "$@" ;;
    *) _release_legacy_bump "$@" ;;
  esac
}

main "$@"
