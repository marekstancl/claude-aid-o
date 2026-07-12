#!/usr/bin/env bash
# aid-plan-close-check.sh — mechanical plan-close self-check.
#
# Replaces the repeated manual fixes the PM has done by hand across AID
# projects (stale/untracked delivery reports, reports claiming a Head that
# is no longer current, queue.yaml/active.md claiming "waiting for merge"
# long after the merge happened, fsm-state.yaml showing DONE with pending
# steps) with ONE invokable script that either passes cleanly, auto-corrects
# what is safely correctable (--auto-annotate, Check 2 only), or fails loud
# with a specific reason.
#
# Usage:
#   aid-plan-close-check.sh <plan_id> [--project-root <path>] [--auto-annotate]
#
#   <plan_id>          e.g. P062 (drives .aid-o/reports/<plan_id>-*.md lookup
#                      and E-<nnn>-* EPIC-id matching, nnn = digits after 'P')
#   --project-root     project root containing .aid-o/ (default: cwd)
#   --auto-annotate    Check 2 ONLY: for a stale-but-docs-only report, rewrite
#                      the frontmatter to add Head_at_generation (old head),
#                      update Head to current HEAD, and write a Head_note.
#                      Idempotent — a report whose Head already equals HEAD
#                      is left untouched on a second run.
#
# Exit code: 0 = all checks pass (or are non-blocking), non-zero = at least
# one blocking failure. Never silent — every check prints PASS/FAIL/INFO.
#
# Reuses (never reimplements):
#   - aid-fsm.sh's `queue_revalidate` / `_queue_parse_to_json` / `yaml_field`
#     for all queue.yaml parsing and dependency merge-detection (Check 4).
#     aid-fsm.sh is sourced, not shelled out to, so this script shares the
#     exact same mixed-indentation-tolerant queue parser aid-fsm.sh itself
#     uses (a plain `yq` pass over queue.yaml is known to choke on the live
#     dogfood format — see test-queue-revalidation.bats scenario (g)).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AID_FSM="${SCRIPT_DIR}/aid-fsm.sh"

# ─────────────────────────────────────────────────────────────────────────
# Check 2 classification regex — anything NOT matching this allow-list is
# treated as code/test and forces "regeneration required" rather than a
# docs-only annotation.
#
# CRITICAL FIX (repo issue #IMP-*): The allow-list must use anchored,
# path-segment-aware patterns to avoid false positives where real code files
# (e.g., src/docs/generator.py, packages/sdk-docs/index.ts) get misclassified
# as docs-only merely because "docs/" appears as a substring in their path.
#
# Patterns (applied via grep -Ev against full relative paths):
#  - README/CHANGELOG: match as basename only, accounting for extensions
#    (e.g., README.md, CHANGELOG.txt). Regex: (^|/)README($|\.) for README.
#  - docs/: match as a path SEGMENT, not a substring. Regex: (^|/)docs/ to
#    match "docs/" at the path root or after a /, but NOT inside a filename
#    like packages/sdk-docs/index.ts.
#  - \.md$: already anchored (suffix match).
#  - Exact paths for .aid-o/ files (backlog.md, queue.yaml, active.md) to
#    avoid ambiguity with similarly-named files in other directories.
# ─────────────────────────────────────────────────────────────────────────
DOCS_ONLY_ALLOW_RE='(^|/)README($|\.)|\.md$|(^|/)CHANGELOG($|\.)|^\.aid-o/work/backlog\.md$|^\.aid-o/config/queue\.yaml$|^\.aid-o/work/active\.md$|(^|/)docs/'

usage() {
  cat >&2 <<'EOF'
Usage: aid-plan-close-check.sh <plan_id> [--project-root <path>] [--auto-annotate]

  <plan_id>          e.g. P062
  --project-root     project root containing .aid-o/ (default: cwd)
  --auto-annotate    Check 2 only: rewrite a stale-but-docs-only report's
                     frontmatter (Head_at_generation + Head + Head_note)
EOF
  exit 2
}

PLAN_ID=""
PROJECT_ROOT="$(pwd)"
AUTO_ANNOTATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ $# -ge 2 ]] || usage; PROJECT_ROOT="$2"; shift 2 ;;
    --auto-annotate) AUTO_ANNOTATE=1; shift ;;
    -h|--help) usage ;;
    -*) echo "Unknown flag: $1" >&2; usage ;;
    *)
      [[ -z "$PLAN_ID" ]] || usage
      PLAN_ID="$1"; shift ;;
  esac
done
[[ -n "$PLAN_ID" ]] || usage

cd "$PROJECT_ROOT"

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required (mikefarah/yq v4)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: not a git repository: $PROJECT_ROOT" >&2; exit 2; }
[[ -f "$AID_FSM" ]] || { echo "ERROR: aid-fsm.sh not found at $AID_FSM" >&2; exit 2; }

# Source (not exec) aid-fsm.sh so we share its exact queue parser
# (_queue_parse_to_json), its dependency-revalidation logic (queue_revalidate,
# _revalidate_one_dep) and its simple scalar-field reader (yaml_field), rather
# than re-implementing any of it. The BASH_SOURCE guard at the bottom of
# aid-fsm.sh skips CLI dispatch when sourced (same mechanism its own bats
# suite relies on), so sourcing here is safe and side-effect-free.
# shellcheck source=/dev/null
source "$AID_FSM"

PLAN_NUM="${PLAN_ID#P}"
REPORTS_DIR=".aid-o/reports"
QUEUE_FILE=".aid-o/config/queue.yaml"
ACTIVE_FILE=".aid-o/work/active.md"

RESULT_LINES=()
OVERALL_RC=0

_pass() { RESULT_LINES+=("PASS  [$1] $2"); }
_fail() { RESULT_LINES+=("FAIL  [$1] $2"); OVERALL_RC=1; }
_info() { RESULT_LINES+=("INFO  [$1] $2"); }

# ═══════════════════════════════════════════════════════════════════════
# Check 1 — official report tracking
# ═══════════════════════════════════════════════════════════════════════

REPORT_STORAGE_MODE=""     # set here, read by Check 2
FOUND_REPORTS=()           # report paths that exist on disk, set here, read by Check 2

# _git_file_status <path> — echoes exactly one of:
#   committed            tracked, in HEAD's tree, no uncommitted changes
#   untracked             never added to the index ("??" in git status)
#   staged_uncommitted    in the index but not yet in any commit
#   modified_uncommitted  in HEAD but has uncommitted changes since
_git_file_status() {
  local f="$1"
  if ! git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    echo "untracked"; return 0
  fi
  if ! git cat-file -e "HEAD:${f}" 2>/dev/null; then
    echo "staged_uncommitted"; return 0
  fi
  if [[ -n "$(git status --porcelain -- "$f" 2>/dev/null)" ]]; then
    echo "modified_uncommitted"; return 0
  fi
  echo "committed"
}

check1_report_tracking() {
  # Per-project runtime detection — reuse `git check-ignore` directly against
  # a probe path under .aid-o/reports/ (the path need not exist on disk for
  # check-ignore to evaluate the ignore patterns against it).
  local probe="${REPORTS_DIR}/__aid_plan_close_probe__"
  if git check-ignore -q "$probe" 2>/dev/null; then
    REPORT_STORAGE_MODE="private/gitignored"
  else
    REPORT_STORAGE_MODE="committed"
  fi

  local delivery="${REPORTS_DIR}/${PLAN_ID}-delivery.md"
  local boundary="${REPORTS_DIR}/${PLAN_ID}-boundary.md"
  local f

  for f in "$delivery" "$boundary"; do
    if [[ ! -f "$f" ]]; then
      if [[ "$f" == "$delivery" ]]; then
        _fail "check1" "$f does not exist — report never generated (report_storage: ${REPORT_STORAGE_MODE})"
      else
        _info "check1" "$f not present (boundary report optional) — report_storage: ${REPORT_STORAGE_MODE}"
      fi
      continue
    fi

    FOUND_REPORTS+=("$f")

    if [[ "$REPORT_STORAGE_MODE" == "private/gitignored" ]]; then
      _pass "check1" "$f present (report_storage: private/gitignored — never a blocker)"
      continue
    fi

    local st; st=$(_git_file_status "$f")
    case "$st" in
      committed)
        _pass "check1" "$f present and committed (report_storage: committed)" ;;
      untracked)
        _fail "check1" "$f exists on disk but is UNTRACKED (report_storage: committed) — git add + commit before plan-close" ;;
      staged_uncommitted)
        _fail "check1" "$f is staged but not part of any commit (report_storage: committed) — commit before plan-close" ;;
      modified_uncommitted)
        _fail "check1" "$f has uncommitted changes since its last commit (report_storage: committed) — commit before plan-close" ;;
    esac
  done
}

# ═══════════════════════════════════════════════════════════════════════
# Check 2 — Head freshness
# ═══════════════════════════════════════════════════════════════════════

# _extract_frontmatter <file> — print the YAML frontmatter block (the lines
# strictly between the first and second "---" delimiter lines), excluding
# the delimiters themselves.
_extract_frontmatter() {
  awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++; if (c==2) exit; next} c==1{print}' "$1"
}

# _yq_frontmatter_field <file> <field> — echoes the field's value from the
# file's frontmatter (empty string if absent). Handles both plain scalars
# (Head: abc123) and folded/literal block scalars (Head_note: >-\n  ...).
_yq_frontmatter_field() {
  local file="$1" field="$2"
  _extract_frontmatter "$file" | yq -r ".${field} // \"\"" - 2>/dev/null
}

# _auto_annotate_report <file> <old_head> <new_head>
# Idempotent, frontmatter-only rewrite: sets Head=<new_head>,
# Head_at_generation=<old_head>, Head_note=<explanation>, leaves the rest of
# the file (including the markdown body) byte-for-byte untouched. Safe to
# call twice in a row for the SAME (old_head, new_head) pair — the second
# call's caller never invokes this because Check 2's Head==current-HEAD
# branch short-circuits before reaching auto-annotate.
_auto_annotate_report() {
  local file="$1" old_head="$2" new_head="$3"
  local commit_summary
  commit_summary=$(git log --format='%h %s' "${old_head}..${new_head}" 2>/dev/null | tac | paste -sd', ' - 2>/dev/null || true)
  [[ -n "$commit_summary" ]] || commit_summary="(no intermediate commits found)"
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local note="Ran against ${old_head:0:7}; commit(s) landed after (${commit_summary}) \
— docs/backlog-only, zero code/test delta. Header corrected automatically \
(aid-plan-close-check.sh --auto-annotate, ${now})."

  local marks m1 m2
  marks=$(grep -n '^---[[:space:]]*$' "$file" | head -2 | cut -d: -f1)
  m1=$(echo "$marks" | sed -n 1p)
  m2=$(echo "$marks" | sed -n 2p)
  if [[ -z "$m1" || -z "$m2" ]]; then
    echo "ERROR: $file has no parseable '---' frontmatter block — cannot auto-annotate" >&2
    return 1
  fi

  local fm_file; fm_file=$(mktemp)
  _extract_frontmatter "$file" > "$fm_file"

  # New keys (Head_at_generation, Head_note, _header_corrected_at) are
  # appended after existing keys by yq — since Head already exists earlier
  # in the file, this reproduces the exact WAN P062-delivery.md field order
  # (Head, Head_at_generation, Head_note, ...).
  yq -i \
    ".Head = \"${new_head}\" | .Head_at_generation = \"${old_head}\" | .Head_note = \"${note}\" | ._header_corrected_at = \"${now}\"" \
    "$fm_file"

  local tmp_out; tmp_out=$(mktemp)
  {
    echo "---"
    cat "$fm_file"
    echo "---"
    tail -n "+$((m2 + 1))" "$file"
  } > "$tmp_out"
  mv "$tmp_out" "$file"
  rm -f "$fm_file"
}

check2_head_freshness() {
  local current_head; current_head=$(git rev-parse HEAD)
  local f
  for f in "${FOUND_REPORTS[@]}"; do
    local recorded_head head_note head_at_gen
    recorded_head=$(_yq_frontmatter_field "$f" "Head")
    head_at_gen=$(_yq_frontmatter_field "$f" "Head_at_generation")
    head_note=$(_yq_frontmatter_field "$f" "Head_note")

    if [[ -z "$recorded_head" ]]; then
      _fail "check2" "$f: frontmatter has no Head field — cannot verify freshness"
      continue
    fi

    if [[ "$recorded_head" == "$current_head" ]]; then
      _pass "check2" "$f: Head (${recorded_head:0:7}) matches current HEAD — fresh, no note needed"
      continue
    fi

    if ! git cat-file -e "${recorded_head}^{commit}" 2>/dev/null; then
      _fail "check2" "$f: Head field ($recorded_head) does not resolve to a commit in this repo — regeneration required"
      continue
    fi

    # Exclude the report file itself from the delta. A report necessarily
    # records a head that predates the commit which persists that very
    # value (a commit cannot embed its own SHA) — so the commit that last
    # wrote/annotated this report is always "one commit behind" its own
    # current HEAD by construction. Without this exclusion Check 2 could
    # never stabilize on PASS for a committed, freshly-annotated report
    # (confirmed against the live WAN P062-delivery.md shape: its recorded
    # Head predates its own `_header_corrected_at` commit).
    local changed
    changed=$(git diff --name-only "${recorded_head}..${current_head}" -- . ":(exclude)${f}" 2>/dev/null || true)
    if [[ -z "$changed" ]]; then
      _pass "check2" "$f: Head (${recorded_head:0:7}) != current HEAD (${current_head:0:7}) but the only delta is this report's own annotation commit — fresh"
      continue
    fi

    # Classify changed files to distinguish CODE (requires regeneration) from
    # DOCS-only (can be annotated). A file is CODE if:
    #   (a) it has a known code extension (.py, .ts, .sh, etc.) — extension-
    #       based classification wins over directory-name patterns, so
    #       src/docs/generator.py is CODE despite the docs/ path segment, or
    #   (b) it doesn't match any of the docs-only patterns.
    # Collect all CODE files in a two-stage filter.
    # Note: .yaml/.yml excluded from code_ext_pattern (too broad, includes
    # config files like queue.yaml which are docs-only via exact-path match).
    local non_docs code_ext_pattern
    code_ext_pattern='\.(sh|py|ts|tsx|js|jsx|go|rs|java|rb|c|cpp|h|hpp|sql|json|xml|toml|gradle|pom|kt|scala|swift|m|mm)$'

    # Stage 1: Extract files with code extensions (always CODE, extension wins).
    local with_code_ext
    with_code_ext=$(echo "$changed" | grep -E "$code_ext_pattern" || true)

    # Stage 2: From remaining files (without code extensions), extract those
    # that DON'T match docs-only patterns (also CODE).
    local without_code_ext without_docs_match
    without_code_ext=$(echo "$changed" | grep -Ev "$code_ext_pattern" || true)
    without_docs_match=$(echo "$without_code_ext" | grep -Ev "$DOCS_ONLY_ALLOW_RE" || true)

    # Union: non_docs = (files with code extension) + (non-extension files not matching docs pattern)
    non_docs=$(printf "%s\n%s" "$with_code_ext" "$without_docs_match" | grep -v '^$' || true)

    if [[ -n "$non_docs" ]]; then
      _fail "check2" "$f: functional (code/test) change(s) landed since Head (${recorded_head:0:7}) — regeneration required. Changed: $(echo "$non_docs" | tr '\n' ' ')"
      continue
    fi

    # All changed paths are docs/backlog/queue-only.
    if [[ "$AUTO_ANNOTATE" -eq 1 ]]; then
      _auto_annotate_report "$f" "$recorded_head" "$current_head"
      _pass "check2" "$f: docs-only delta since Head (${recorded_head:0:7}) — auto-annotated (Head -> ${current_head:0:7})"
    elif [[ -n "$head_at_gen" && -n "$head_note" ]]; then
      _fail "check2" "$f: Head_at_generation/Head_note already present but Head field itself is still stale (${recorded_head:0:7} != ${current_head:0:7}) after a further docs-only delta — needs re-annotation (run with --auto-annotate)"
    else
      _fail "check2" "$f: Head (${recorded_head:0:7}) stale but delta since is docs-only — needs Head_at_generation + Head + Head_note annotation (run with --auto-annotate)"
    fi
  done
}

# ═══════════════════════════════════════════════════════════════════════
# Check 3 — fsm-state.yaml DONE-but-pending guard
# ═══════════════════════════════════════════════════════════════════════

check3_fsm_done_pending() {
  local evidence_root=".aid-o/work/evidence"
  [[ -d "$evidence_root" ]] || { _info "check3" "no ${evidence_root}/ — Check 3 N/A"; return 0; }

  local dir found_any=0
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    found_any=1
    local f
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      local state; state=$(yaml_field "$f" state)
      if [[ "$state" != "DONE" ]]; then
        _info "check3" "$f: state=${state:-unknown} (not DONE) — Check 3 N/A"
        continue
      fi
      if ! yq -e '.steps' "$f" >/dev/null 2>&1; then
        _info "check3" "$f: state=DONE, legacy fsm-state (no steps[] array) — skipped"
        continue
      fi
      local pending_count
      pending_count=$(yq -r '[.steps[]? | select(.status=="pending")] | length' "$f" 2>/dev/null || echo 0)
      if [[ "${pending_count:-0}" -gt 0 ]]; then
        _fail "check3" "$f: state=DONE but ${pending_count} step(s) still status:pending"
      else
        _pass "check3" "$f: state=DONE, all steps completed"
      fi
    done < <(find "$dir" -maxdepth 2 -name fsm-state.yaml 2>/dev/null)
  done < <(find "$evidence_root" -maxdepth 1 -type d -name "E-${PLAN_NUM}-*" 2>/dev/null)

  [[ "$found_any" -eq 1 ]] || _info "check3" "no evidence dirs matching E-${PLAN_NUM}-* under ${evidence_root}/ — Check 3 N/A"
}

# ═══════════════════════════════════════════════════════════════════════
# Check 4 — queue.yaml / active.md revalidation
# ═══════════════════════════════════════════════════════════════════════

# _probe_epic_merged <epic_id> — reuses queue_revalidate (never reimplements
# its ancestor/merged-log detection) to answer "is <epic_id>'s own branch
# actually merged?" queue_revalidate's public contract only revalidates the
# depends_on of the epic_id you pass it, so we append one throwaway queue
# entry that depends_on exactly the epic under test, in the SAME top-level
# "- epic_id:" list-item shape the live dogfood queue.yaml and
# test-queue-revalidation.bats fixtures already use, then ask
# queue_revalidate to resolve THAT synthetic entry's single dependency.
# Echoes: unblocked | blocked | failed | noop.
_probe_epic_merged() {
  local epic="$1"
  local tmp_queue tmp_tl result rc=0
  tmp_queue=$(mktemp)
  tmp_tl=$(mktemp)
  {
    cat "$QUEUE_FILE" 2>/dev/null
    echo
    cat <<YAML
- epic_id: __aid_plan_close_probe__
  path: p
  status: queued
  depends_on: ["${epic}"]
YAML
  } > "$tmp_queue"
  result=$(queue_revalidate "__aid_plan_close_probe__" "$tmp_queue" "$tmp_tl") || rc=$?
  rm -f "$tmp_queue" "$tmp_tl"
  echo "$result"
  return "$rc"
}

check4_queue_revalidate() {
  if [[ ! -f "$QUEUE_FILE" ]]; then
    _info "check4" "no ${QUEUE_FILE} — Check 4 N/A"
    return 0
  fi

  local queue_json
  queue_json=$(_queue_parse_to_json "$QUEUE_FILE")
  if ! echo "$queue_json" | jq -e . >/dev/null 2>&1; then
    _fail "check4" "${QUEUE_FILE} is unparseable — cannot revalidate"
    return 0
  fi

  local epics
  epics=$(echo "$queue_json" | jq -r --arg re "^E-${PLAN_NUM}-" '.[] | select(.epic_id | test($re)) | .epic_id')
  if [[ -z "$epics" ]]; then
    _info "check4" "no queue.yaml entries matching E-${PLAN_NUM}-* — Check 4 N/A"
    return 0
  fi

  local epic
  while IFS= read -r epic; do
    [[ -n "$epic" ]] || continue
    local status_text
    status_text=$(echo "$queue_json" | jq -r --arg e "$epic" '[.[] | select(.epic_id==$e) | .status] | .[0] // ""')

    local active_hit=""
    if [[ -f "$ACTIVE_FILE" ]] && grep -qiE "${epic}.*(blocked|waiting[ _-]?for[ _-]?merge)" "$ACTIVE_FILE"; then
      active_hit="yes"
    fi

    if ! echo "$status_text" | grep -qiE 'blocked|waiting' && [[ -z "$active_hit" ]]; then
      _info "check4" "$epic: queue status='${status_text:-n/a}' — no blocked/waiting claim, nothing to revalidate"
      continue
    fi

    local rc=0 result
    result=$(_probe_epic_merged "$epic") || rc=$?
    case "$result" in
      unblocked)
        _fail "check4" "$epic: queue/active claims blocked/waiting-for-merge (status='${status_text}', active.md hit=${active_hit:-no}) but queue_revalidate confirms the branch IS merged (ancestor of main) — sync queue.yaml/active.md"
        ;;
      blocked)
        _pass "check4" "$epic: queue/active claims blocked/waiting-for-merge — queue_revalidate confirms genuinely unmerged, consistent"
        ;;
      failed|noop|*)
        _info "check4" "$epic: queue/active claims blocked/waiting-for-merge but queue_revalidate could not determine merge status (result='${result}', rc=${rc}) — inconclusive, not flagged"
        ;;
    esac
  done <<< "$epics"
}

# ═══════════════════════════════════════════════════════════════════════
# Aggregate
# ═══════════════════════════════════════════════════════════════════════

main() {
  check1_report_tracking
  check2_head_freshness
  check3_fsm_done_pending
  check4_queue_revalidate

  echo "=== aid-plan-close-check: ${PLAN_ID} ==="
  local line
  for line in "${RESULT_LINES[@]}"; do
    echo "$line"
  done
  echo "---"
  if [[ "$OVERALL_RC" -eq 0 ]]; then
    echo "OVERALL: PASS — plan-close clear (0 blocking failures)"
  else
    local n_fail=0
    for line in "${RESULT_LINES[@]}"; do
      [[ "$line" == FAIL* ]] && n_fail=$((n_fail + 1))
    done
    echo "OVERALL: FAIL — ${n_fail} blocking failure(s), plan-close BLOCKED"
  fi
  exit "$OVERALL_RC"
}

main
