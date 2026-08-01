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
Usage: aid-plan-close-check.sh <plan_id> [--project-root <path>] [--auto-annotate] [--skip-delivery-report]

  <plan_id>              e.g. P062
  --project-root         project root containing .aid-o/ (default: cwd)
  --auto-annotate        Check 2 only: rewrite a stale-but-docs-only report's
                         frontmatter (Head_at_generation + Head + Head_note)
  --plan-branch          P068 Step 6: additionally run Check 5, the plan-branch
                         close boundary (EPIC terminality + ancestry, the
                         plan-final evidence bound to candidate_sha, the C4 and
                         PM decisions, the merge-or-abort record, the tag state,
                         MERGE_HEAD, unfinished operation records, held locks
                         and the .aid-lifecycle receipt reconciliation).
  --close-mode <m>       merge|abort — which terminal shape Check 5 verifies
                         (default: merge). Only meaningful with --plan-branch.
  --exclude-lock <path>  Check 5's lock-contention probe SKIPS this exact
                         canonical path. The close transaction holds its OWN
                         lock for the whole transaction, so probing that one
                         would contend with the caller and never pass; the
                         exclusion is by exact path, so a DIFFERENT lock held
                         by the same process still blocks. May be given at
                         most once, and only for this plan's own
                         plan-close.lock — the exclusion cannot be widened.
  --skip-delivery-report Caller has reporter.enabled:false — a missing
                         delivery/boundary report is expected and must NOT
                         fail Check 1. Only the report-existence requirement
                         is relaxed; Check 1 still validates tracking/
                         freshness for a report that DOES exist on disk, and
                         Checks 2-4 (Head freshness, fsm-state DONE-pending,
                         queue/active revalidation) are UNAFFECTED — this
                         flag never widens into skipping the whole script.
EOF
  exit 2
}

PLAN_ID=""
PROJECT_ROOT="$(pwd)"
AUTO_ANNOTATE=0
SKIP_DELIVERY_REPORT=0
PLAN_BRANCH_MODE=0
CLOSE_MODE="merge"
CLOSE_OP_ID=""
EXCLUDE_LOCKS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ $# -ge 2 ]] || usage; PROJECT_ROOT="$2"; shift 2 ;;
    --auto-annotate) AUTO_ANNOTATE=1; shift ;;
    --plan-branch) PLAN_BRANCH_MODE=1; shift ;;
    --close-mode) [[ $# -ge 2 ]] || usage; CLOSE_MODE="$2"; shift 2 ;;
    --exclude-lock) [[ $# -ge 2 ]] || usage; EXCLUDE_LOCKS+=("$2"); shift 2 ;;
    --close-op-id) [[ $# -ge 2 ]] || usage; CLOSE_OP_ID="$2"; shift 2 ;;
    --skip-delivery-report) SKIP_DELIVERY_REPORT=1; shift ;;
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

# P068 Step 6: Check 5 reads the git-tracked `.aid-lifecycle` layer through its
# OWN canonical resolver (aid_plan_closure_state) rather than re-deriving
# closability here — the whole point of the check is that the two state systems
# agree. Sourced only in --plan-branch mode so the legacy invocation keeps its
# exact dependency surface. Both project-root knobs are set because the plan
# libraries read one and the manifest library the other.
if [[ "$PLAN_BRANCH_MODE" -eq 1 ]]; then
  export AID_PLAN_STATE_PROJECT_ROOT="$PROJECT_ROOT"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$PROJECT_ROOT"
  if ! declare -F aid_plan_closure_state >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/lib/aid-lifecycle.sh"
  fi
  # D4 round-2 Codex MEDIUM: reuse D1's OWN receipt-schema/inventory
  # validators (aid-plan-fsm.sh) rather than a shorter ad-hoc re-check here —
  # two independent implementations of "is this receipt well-formed" drift
  # apart over time, and the ad-hoc version was missing key-set and per-output
  # hash-shape checks the real D1 verifier enforces. The BASH_SOURCE guard at
  # the bottom of aid-plan-fsm.sh skips CLI dispatch when sourced, same as
  # aid-fsm.sh above, so this is side-effect-free.
  if ! declare -F _pfsm_validate_plan_final_receipt_json >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/aid-plan-fsm.sh"
  fi
fi

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
        if [[ "$SKIP_DELIVERY_REPORT" -eq 1 ]]; then
          _info "check1" "$f does not exist — reporter.enabled:false (--skip-delivery-report), not a blocker"
        else
          _fail "check1" "$f does not exist — report never generated (report_storage: ${REPORT_STORAGE_MODE})"
        fi
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
#
# SECURITY: All runtime values (note with commit subjects) are passed via
# environment variables + yq's strenv() to prevent yq expression injection
# from special characters in free-form text (e.g., commit subjects with
# quotes, backslashes, or other shell metacharacters).
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
  # Pass all values via environment variables + strenv() to safely escape
  # special characters in runtime text (commit subjects, etc.).
  HEAD_VALUE="$new_head" \
  HEAD_AT_GENERATION="$old_head" \
  HEAD_NOTE="$note" \
  HEADER_CORRECTED_AT="$now" \
  yq -i '
    .Head = strenv(HEAD_VALUE) |
    .Head_at_generation = strenv(HEAD_AT_GENERATION) |
    .Head_note = strenv(HEAD_NOTE) |
    ._header_corrected_at = strenv(HEADER_CORRECTED_AT)
  ' "$fm_file"

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

# D4 / IMP-467: is THIS candidate covered by a durable, verified D1 plan-final
# evidence receipt? Only then does grouped freshness apply — a plan/mode
# without a receipt (legacy, or plan_branch before D1 ran) keeps today's
# exact per-report-only-self-exclusion behavior. This is the FULL binding
# _pfsm_verify_plan_final_receipt (aid-plan-fsm.sh, D1) enforces at
# merge/close time — the derived ref path, exact receipt schema/keys,
# review_verdict, and plan_id/candidate_sha/run_id/evidence_ref all bound to
# the manifest's OWN recorded candidate/run — not a looser freshness-only
# shortcut that would accept any resolvable single-file ref.
_check2_receipt_covers_candidate() {
  [[ "$PLAN_BRANCH_MODE" -eq 1 ]] || return 1
  local plan_id candidate run_id ref hash receipt tree expected_ref
  plan_id="$(_pbm '.plan_boundary_manifest.plan_id')"
  candidate="$(_pbm '.plan_boundary_manifest.candidate_sha')"
  run_id="$(_pbm '.plan_boundary_manifest.plan_final_run_id')"
  [[ "$plan_id" =~ ^P[0-9]{3}$ && "$candidate" =~ ^[0-9a-f]{40}$ && -n "$run_id" ]] || return 1
  # D4 round-2 Codex HIGH: the manifest's OWN plan_id field is content on
  # disk, not proof of which plan this check is running for — PLAN_ID (the
  # CLI-selected plan this whole script invocation is scoped to) is the only
  # trustworthy anchor. Without this, a manifest under plan-state/P467/ that
  # internally claims plan_id:"P123" would derive expected_ref from "P123",
  # match a real old P123 receipt, and grant P467's reports grouped
  # freshness from evidence that was never about P467 at all.
  [[ "$plan_id" == "$PLAN_ID" ]] || return 1
  expected_ref="refs/heads/aid-evidence/${plan_id}/${candidate}/${run_id}"
  ref="$(_pbm '.plan_boundary_manifest.plan_final_evidence_ref')"
  hash="$(_pbm '.plan_boundary_manifest.plan_final_evidence_receipt_sha256')"
  [[ -n "$ref" && "$ref" == "$expected_ref" && -n "$hash" ]] || return 1
  receipt="$(git show "${ref}:receipt.json" 2>/dev/null)" || return 1
  tree="$(git ls-tree -r --name-only "${ref}" 2>/dev/null || true)"
  [[ "$tree" == "receipt.json" ]] || return 1
  [[ "sha256:$(printf '%s\n' "$receipt" | sha256sum | awk '{print $1}')" == "$hash" ]] || return 1
  # D4 round-2 Codex MEDIUM: reuse D1's OWN full schema/key-set validator
  # (aid-plan-fsm.sh) instead of a shorter ad-hoc re-check — the ad-hoc
  # version accepted extra/renamed keys and malformed per-output hash
  # shapes that D1's own verifier would reject. D4 round-4 Codex MEDIUM:
  # also reuse _pfsm_receipt_has_exact_review_inventory again — it is now
  # schema-version-FROZEN (not derived from the live
  # _pfsm_review_required_outputs), so it no longer risks retroactively
  # invalidating a receipt sealed by an older plugin version.
  _pfsm_validate_plan_final_receipt_json "$receipt" || return 1
  _pfsm_receipt_has_exact_review_inventory "$receipt" || return 1
  local base target target_head frozen_at
  base="$(_pbm '.plan_boundary_manifest.plan_base_commit')"
  target="$(_pbm '.plan_boundary_manifest.target_branch')"
  target_head="$(_pbm '.plan_boundary_manifest.target_branch_head_at_candidate_freeze')"
  frozen_at="$(_pbm '.plan_boundary_manifest.candidate_frozen_at')"
  jq -e --arg p "$plan_id" --arg c "$candidate" --arg r "$run_id" --arg ref "$ref" \
        --arg b "$base" --arg t "$target" --arg th "$target_head" --arg fa "$frozen_at" '
    (.plan_id == $p) and (.candidate_sha == $c) and (.run_id == $r) and
    (.evidence_ref == $ref) and (.plan_base_commit == $b) and
    (.target_branch == $t) and (.target_head_at_freeze == $th) and
    (.candidate_frozen_at == $fa)
  ' <<< "$receipt" >/dev/null 2>&1
}

check2_head_freshness() {
  local current_head; current_head=$(git rev-parse HEAD)
  local _grouped=0
  _check2_receipt_covers_candidate && _grouped=1
  # D4: the receipt-bound group's own paths, ALL of them — not just "this
  # report" — are excluded from every group member's delta. A sibling
  # report's annotation commit touches ONLY that sibling's path, so once the
  # group is excluded as a whole, no member ever sees another member's
  # annotation as drift, and the false "the sibling's commit means I am
  # stale too" oscillation cannot start.
  local -a _group_excl=()
  if [[ "$_grouped" -eq 1 ]]; then
    local _gf
    for _gf in "${FOUND_REPORTS[@]}"; do _group_excl+=(":(exclude)${_gf}"); done
  fi
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

    # Exclude the report file itself from the delta (legacy: just itself; D4
    # grouped: the WHOLE receipt-bound report group). A report necessarily
    # records a head that predates the commit which persists that very
    # value (a commit cannot embed its own SHA) — so the commit that last
    # wrote/annotated this report is always "one commit behind" its own
    # current HEAD by construction. Without this exclusion Check 2 could
    # never stabilize on PASS for a committed, freshly-annotated report
    # (confirmed against the live WAN P062-delivery.md shape: its recorded
    # Head predates its own `_header_corrected_at` commit).
    local changed
    if [[ "$_grouped" -eq 1 ]]; then
      changed=$(git diff --name-only "${recorded_head}..${current_head}" -- . "${_group_excl[@]}" 2>/dev/null || true)
    else
      changed=$(git diff --name-only "${recorded_head}..${current_head}" -- . ":(exclude)${f}" 2>/dev/null || true)
    fi
    if [[ -z "$changed" ]]; then
      if [[ "$_grouped" -eq 1 ]]; then
        _pass "check2" "$f: Head (${recorded_head:0:7}) != current HEAD (${current_head:0:7}) but the only delta is within the receipt-bound report group's own annotation commits — fresh"
      else
        _pass "check2" "$f: Head (${recorded_head:0:7}) != current HEAD (${current_head:0:7}) but the only delta is this report's own annotation commit — fresh"
      fi
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
# Check 5 — the plan-branch close boundary (P068 E-068-1_2 Step 6)
# ═══════════════════════════════════════════════════════════════════════
#
# Checks 1-4 are the LEGACY marker world: reports, their freshness, DONE-but-
# pending EPIC state files, and queue/active consistency. Check 5 is the
# plan-branch world: the runtime plan-boundary manifest, the plan-final
# evidence, the C4 and PM decisions, the published merge (or the recorded
# abort), the tag, and the git-tracked `.aid-lifecycle` layer. Neither used to
# read the other; plan-close is the one place they must agree, so BOTH run and
# a failure in either blocks.
#
# Every sub-check is INDEPENDENTLY blocking and names itself, because AC7 is
# precisely "individually removing or corrupting <one thing> blocks close" —
# a single aggregated verdict could not distinguish which thing.

PLAN_STATE_DIR=".aid-o/work/plan-state/${PLAN_ID}"
PLAN_MANIFEST_JSON="${PLAN_STATE_DIR}/plan-boundary-manifest.json"

# CP2 M1: --exclude-lock exists for exactly one purpose — letting the close
# transaction skip the lock it is itself holding. Unvalidated and repeatable, it
# was a command-line switch that disarmed 5.10 entirely while the script still
# printed "no relevant lock is held". This script is a PM-runnable tool and its
# output is evidence, so the exclusion is constrained to that one sidecar.
# (Top-level scope — `local` is a function builtin and is a hard error here.)
if [[ ${#EXCLUDE_LOCKS[@]} -gt 1 ]]; then
  echo "ERROR: --exclude-lock may be given at most once — it exists only to skip the close transaction's own lock (got ${#EXCLUDE_LOCKS[@]})" >&2
  exit 2
fi
if [[ ${#EXCLUDE_LOCKS[@]} -eq 1 ]]; then
  _excl_raw="${EXCLUDE_LOCKS[0]}"
  _excl_expected="${PLAN_STATE_DIR}/plan-close.lock"
  _excl_c="$(readlink -f -- "$_excl_raw" 2>/dev/null || printf '%s' "$_excl_raw")"
  _excl_e="$(readlink -f -- "$_excl_expected" 2>/dev/null || printf '%s' "$_excl_expected")"
  if [[ "$_excl_c" != "$_excl_e" ]]; then
    echo "ERROR: --exclude-lock '${_excl_raw}' is not this plan's close sidecar (${_excl_expected}) — the exclusion cannot be widened" >&2
    exit 2
  fi
fi

# _pbm <jq_path> — a field of the runtime plan-boundary manifest payload, or
# the empty string. Never aborts under `set -e`.
_pbm() {
  [[ -f "$PLAN_MANIFEST_JSON" ]] || { echo ""; return 0; }
  local v; v="$(jq -r "${1} // \"\"" "$PLAN_MANIFEST_JSON" 2>/dev/null || true)"
  [[ "$v" == "null" ]] && v=""
  printf '%s' "$v"
}

# _lock_is_held <path> — 0 iff a NON-BLOCKING flock acquire fails, i.e. the
# advisory lock is still held by a live open file description.
#
# This is deliberately NOT "does a .lock file exist". flock releases when the
# descriptor closes, not when the file is unlinked, so the `.lock` sidecars the
# plan transactions create persist on disk for the life of the workspace BY
# DESIGN (this very repository carries such files under .aid-o/metrics/).
# Requiring their absence would make plan-close unsatisfiable for every plan
# that ever ran a transaction.
_lock_is_held() {
  local p="$1" fd
  command -v flock >/dev/null 2>&1 || return 1
  # CP2 L1: without this, `exec {fd}<>"$p"` CREATES the sidecar when the path
  # vanished between the find(1) that listed it and this probe — a read-only
  # check must not write to the workspace it is judging.
  [[ -e "$p" ]] || return 1
  exec {fd}<>"$p" 2>/dev/null || return 1
  if flock -n "$fd" 2>/dev/null; then
    flock -u "$fd" 2>/dev/null || true
    eval "exec ${fd}>&-" 2>/dev/null || true
    return 1
  fi
  eval "exec ${fd}>&-" 2>/dev/null || true
  return 0
}

check5_plan_branch_boundary() {
  # ── 5.0 the runtime manifest itself ────────────────────────────────────
  if [[ ! -f "$PLAN_MANIFEST_JSON" ]]; then
    _fail "check5" "no runtime plan-boundary manifest at ${PLAN_MANIFEST_JSON} — there is nothing to close against"
    return 0
  fi
  if ! jq -e '.plan_boundary_manifest | type == "object"' "$PLAN_MANIFEST_JSON" >/dev/null 2>&1; then
    _fail "check5" "${PLAN_MANIFEST_JSON} is not a parseable plan-boundary manifest — close is blocked"
    return 0
  fi
  _pass "check5" "runtime plan-boundary manifest present and parseable"

  local candidate run_id run_dir target_branch plan_branch
  candidate="$(_pbm '.plan_boundary_manifest.candidate_sha')"
  run_id="$(_pbm '.plan_boundary_manifest.plan_final_run_id')"
  run_dir="$(_pbm '.plan_boundary_manifest.plan_final_evidence_dir')"
  target_branch="$(_pbm '.plan_boundary_manifest.target_branch')"
  plan_branch="$(_pbm '.plan_boundary_manifest.plan_branch')"
  [[ -n "$plan_branch" ]] || plan_branch="plan/${PLAN_ID}"

  local f
  for f in candidate run_id run_dir target_branch; do
    if [[ -z "${!f}" ]]; then
      _fail "check5" "the manifest has no ${f} — the plan-final candidate binding is gone, close is blocked"
      return 0
    fi
  done

  # ── 5.1 every EPIC has a terminal status ───────────────────────────────
  local nonterminal
  nonterminal="$(jq -r '[.plan_boundary_manifest.epic_runs[]? | select(.status != "merged_to_plan" and .status != "abandoned" and .status != "superseded") | .epic_id + "(" + (.status // "unknown") + ")"] | join(", ")' "$PLAN_MANIFEST_JSON" 2>/dev/null || true)"
  if [[ -n "$nonterminal" ]]; then
    _fail "check5" "non-terminal EPIC(s): ${nonterminal} — every EPIC must be terminal before the plan closes"
  else
    _pass "check5" "every epic_runs[] entry carries a terminal status"
  fi

  # ── 5.2 every non-abandoned EPIC's merge commit is an ancestor of the
  #        plan branch. UNKNOWN ancestry (a rewritten or missing ref) BLOCKS —
  #        unknown is never treated as merged. ─────────────────────────────
  local eid mc bad=""
  while read -r eid mc; do
    [[ -n "$eid" ]] || continue
    if [[ -z "$mc" || "$mc" == "null" ]]; then
      bad="${bad:+${bad}, }${eid}(no merge commit recorded)"; continue
    fi
    if ! git cat-file -e "${mc}^{commit}" 2>/dev/null; then
      bad="${bad:+${bad}, }${eid}(merge commit ${mc:0:8} does not resolve — ancestry UNKNOWN)"; continue
    fi
    if ! git merge-base --is-ancestor "$mc" "$plan_branch" 2>/dev/null; then
      bad="${bad:+${bad}, }${eid}(${mc:0:8} is not an ancestor of ${plan_branch})"
    fi
  done < <(jq -r '.plan_boundary_manifest.epic_runs[]? | select(.status == "merged_to_plan") | .epic_id + " " + (.epic_merge_commit // "")' "$PLAN_MANIFEST_JSON" 2>/dev/null || true)
  if [[ -n "$bad" ]]; then
    _fail "check5" "EPIC ancestry is not provable against ${plan_branch}: ${bad}"
  else
    _pass "check5" "every merged EPIC's merge commit is an ancestor of ${plan_branch}"
  fi

  # ── 5.3 the plan-final run directory: the gate report + every required
  #        review artifact, still byte-identical to what the review recorded
  #        against candidate_sha ─────────────────────────────────────────
  # IMP-466 item 4: a genuinely lost runtime (deleted .aid-o/work, new
  # worktree, fresh clone) after a REAL merge has no run_dir left at all —
  # not a corrupted one, a GONE one. The durable close-evidence receipt
  # (sealed by plan-merge-to-main from these exact facts) is the ONLY thing
  # that lets 5.3/5.4/5.5 pass in that case, and only for a merge close: it
  # is verified in full (ref location, tree shape, hash, schema, plan/
  # candidate/run binding) before a single PASS is granted on its behalf.
  local close_evidence_ok=0 ce_receipt=""
  if [[ ! -d "$run_dir" && "$CLOSE_MODE" != "abort" ]]; then
    local ce_ref ce_hash ce_tree ce_expected_ref
    ce_ref="$(_pbm '.plan_boundary_manifest.plan_final_close_evidence_ref')"
    ce_hash="$(_pbm '.plan_boundary_manifest.plan_final_close_evidence_receipt_sha256')"
    ce_expected_ref="refs/heads/aid-evidence-close/${PLAN_ID}/${candidate}/${run_id}"
    if [[ -n "$ce_ref" && -n "$ce_hash" && "$ce_ref" == "$ce_expected_ref" ]] \
       && ce_receipt="$(git show "${ce_ref}:receipt.json" 2>/dev/null)" \
       && ce_tree="$(git ls-tree -r --name-only "${ce_ref}" 2>/dev/null)" && [[ "$ce_tree" == "receipt.json" ]] \
       && [[ "sha256:$(printf '%s\n' "$ce_receipt" | sha256sum | awk '{print $1}')" == "$ce_hash" ]] \
       && jq -e --arg p "$PLAN_ID" --arg c "$candidate" --arg r "$run_id" --arg tb "$target_branch" \
            '((keys | sort) == (["artifact_type","candidate_sha","gates_verdict","merge_commit","merged_tree","pm_decision","c4_decision","plan_id","run_id","schema_version","tag","target_branch","target_head_before"] | sort)) and (.schema_version == "aid-plan-final-close-evidence-1") and (.artifact_type == "plan_final_close_evidence_receipt") and (.plan_id == $p) and (.candidate_sha == $c) and (.run_id == $r) and (.target_branch == $tb) and (.gates_verdict == "pass") and (.c4_decision.release_ready == true) and (.c4_decision.dual_run_match == true) and (.pm_decision.decision == "MERGE")' \
            <<< "$ce_receipt" >/dev/null 2>&1; then
      close_evidence_ok=1
      _pass "check5" "the plan-final run directory is gone, but a verified durable close-evidence receipt (${ce_ref}) attests gates=pass, C4 release_ready with a matched dual-run, and a PM MERGE decision"
    else
      _fail "check5" "the plan-final run directory ${run_dir} does not exist and no valid durable close-evidence receipt covers it — the evidence this close would attest to is gone"
    fi
  elif [[ ! -d "$run_dir" ]]; then
    _fail "check5" "the plan-final run directory ${run_dir} does not exist — the evidence this close would attest to is gone"
  else
    local gr="${run_dir}/gates_report.json"
    if [[ ! -f "$gr" ]]; then
      _fail "check5" "no plan-final gate report at ${gr}"
    elif ! jq -e '(.overall // .gates_report.result // .status // "") == "pass"' "$gr" >/dev/null 2>&1; then
      _fail "check5" "${gr} does not record an overall pass"
    else
      _pass "check5" "the plan-final gate report is present and records a pass"
    fi

    local rev_run rev_cand
    rev_run="$(_pbm '.plan_boundary_manifest.plan_final_review.run_id')"
    rev_cand="$(_pbm '.plan_boundary_manifest.plan_final_review.candidate_sha')"
    if [[ -z "$rev_run" ]]; then
      _fail "check5" "the manifest records no plan_final_review — the plan-level review boundary was never completed for this attempt"
    elif [[ "$rev_run" != "$run_id" || "$rev_cand" != "$candidate" ]]; then
      _fail "check5" "the recorded plan_final_review is bound to run '${rev_run}' / candidate ${rev_cand:0:8}, not to this attempt '${run_id}' / candidate ${candidate:0:8}"
    else
      local rf rsha actual missing="" corrupt=""
      while read -r rf rsha; do
        [[ -n "$rf" ]] || continue
        if [[ ! -f "${run_dir}/${rf}" ]]; then
          missing="${missing:+${missing}, }${rf}"; continue
        fi
        actual="sha256:$(sha256sum "${run_dir}/${rf}" 2>/dev/null | awk '{print $1}')"
        [[ "$actual" == "$rsha" ]] || corrupt="${corrupt:+${corrupt}, }${rf}"
      done < <(jq -r '.plan_boundary_manifest.plan_final_review.outputs // {} | to_entries[] | .key + " " + .value' "$PLAN_MANIFEST_JSON" 2>/dev/null || true)
      if [[ -n "$missing" ]]; then
        _fail "check5" "required plan-final review output(s) missing from ${run_dir}: ${missing}"
      fi
      if [[ -n "$corrupt" ]]; then
        _fail "check5" "required plan-final review output(s) no longer match the hash recorded at review time (corrupted or regenerated after the candidate was reviewed): ${corrupt}"
      fi
      [[ -z "$missing" && -z "$corrupt" ]] && \
        _pass "check5" "every required plan-final review output is present and bound to candidate ${candidate:0:8}"
    fi

    # ── 5.4 the plan-mode C4 decision, and the legacy release path ────────
    local c4_run c4_cand
    c4_run="$(_pbm '.plan_boundary_manifest.plan_final_c4.run_id')"
    c4_cand="$(_pbm '.plan_boundary_manifest.plan_final_c4.candidate_sha')"
    if [[ ! -f "${run_dir}/release-decision.json" ]]; then
      _fail "check5" "no plan-mode C4 decision at ${run_dir}/release-decision.json"
    elif [[ "$c4_run" != "$run_id" || "$c4_cand" != "$candidate" ]]; then
      _fail "check5" "the recorded plan_final_c4 is bound to run '${c4_run}' / candidate ${c4_cand:0:8}, not to this attempt"
    else
      _pass "check5" "a plan-mode C4 decision exists for this attempt's candidate"
    fi
    local dual="${run_dir}/release-decision-dual-run.json"
    if [[ ! -f "$dual" ]]; then
      _fail "check5" "no ${dual} — the currently authoritative legacy release path has no recorded verdict"
    elif ! jq -e '.legacy_verdict == true' "$dual" >/dev/null 2>&1; then
      _fail "check5" "${dual} records legacy_verdict != true — the currently authoritative legacy release path did NOT pass"
    else
      _pass "check5" "the legacy release path recorded a pass for this attempt"
    fi
  fi

  # ── 5.5 the PM decision ────────────────────────────────────────────────
  local pmd="${run_dir}/pm-plan-decision.json"
  local terminal_reason; terminal_reason="$(_pbm '.plan_boundary_manifest.terminal_reason')"
  if [[ "$CLOSE_MODE" == "abort" ]]; then
    if [[ -z "$terminal_reason" ]]; then
      _fail "check5" "abort close: the manifest records no terminal_reason — an aborted plan closes only with a recorded reason"
    else
      _pass "check5" "abort close: the terminal reason is recorded (${terminal_reason})"
    fi
  elif [[ "$close_evidence_ok" -eq 1 ]]; then
    _pass "check5" "no run directory, but the verified durable close-evidence receipt already attests a bound PM MERGE decision"
  else
    if [[ ! -f "$pmd" ]]; then
      _fail "check5" "no PM decision recorded at ${pmd} — plan-merge-to-main copies the authorization it validated into the attempt's run directory; without it this close has no proof a PM authorized anything"
    elif ! jq -e --arg p "$PLAN_ID" --arg r "$run_id" --arg c "$candidate" \
              '.plan_id == $p and .plan_final_run_id == $r and .candidate_sha == $c and .decision == "MERGE"' \
              "$pmd" >/dev/null 2>&1; then
      _fail "check5" "the PM decision at ${pmd} is not a MERGE authorization bound to ${PLAN_ID} / ${run_id} / ${candidate:0:8}"
    else
      _pass "check5" "a PM MERGE decision bound to this plan, attempt and candidate is recorded"
    fi
  fi

  # ── 5.6 the merge (or abort) record, and the ancestry it claims ────────
  local merge_result merge_commit target_head_now
  merge_result="$(_pbm '.plan_boundary_manifest.plan_final_merge.result')"
  merge_commit="$(_pbm '.plan_boundary_manifest.plan_final_merge.merge_commit')"
  target_head_now="$(git rev-parse --verify --quiet "refs/heads/${target_branch}" 2>/dev/null || true)"
  if [[ "$CLOSE_MODE" == "abort" ]]; then
    local frozen_target; frozen_target="$(_pbm '.plan_boundary_manifest.target_branch_head_at_candidate_freeze')"
    if [[ -n "$merge_result" && "$merge_result" == "merged" ]]; then
      _fail "check5" "abort close requested, but the manifest records a PUBLISHED merge (${merge_commit:0:8}) — an aborted plan never merged"
    elif [[ -z "$frozen_target" || -z "$target_head_now" ]]; then
      # CP2 H2: this used to fall through to the PASS below, printing "the target
      # branch is unchanged" while having skipped the only check that could say
      # so. `target_branch_head_at_candidate_freeze` is genuinely nullable (every
      # candidate invalidation resets it), so the degenerate case is reachable —
      # and "cannot verify" must never read as "verified".
      _fail "check5" "abort close: the target-branch head at candidate freeze is not recorded (frozen='${frozen_target:-<none>}', live='${target_head_now:-<unresolvable>}') — whether ${target_branch} is unchanged cannot be established, so close is blocked rather than assumed"
    elif [[ "$frozen_target" == "$target_head_now" ]]; then
      _pass "check5" "abort close: no merge was published and ${target_branch} is unchanged"
    else
      # CP2 H1: the abort transaction itself commits `status: aborted` onto the
      # target branch, so a successful abort close ALWAYS advances the target by
      # its own lifecycle commit. A bare "moved => fail" made abort single-shot
      # (any re-run, including the crash-resume the error message prescribes,
      # was permanently refused). What 5.6 actually means for an abort is that no
      # PLAN CONTENT was published — so accept exactly the abort's own lifecycle
      # commits: a fast-forward from the frozen head whose every commit touches
      # nothing but this plan's lifecycle manifest.
      local _ab_ok=1 _ab_c _ab_files
      if ! git merge-base --is-ancestor "$frozen_target" "$target_head_now" 2>/dev/null; then
        _ab_ok=0
      else
        while IFS= read -r _ab_c; do
          [[ -n "$_ab_c" ]] || continue
          _ab_files="$(git show --pretty=format: --name-only "$_ab_c" 2>/dev/null | grep -v '^$' | sort -u)"
          if [[ "$_ab_files" != ".aid-lifecycle/manifests/${PLAN_ID}.yaml" ]]; then
            _ab_ok=0; break
          fi
        done < <(git rev-list "${frozen_target}..${target_head_now}" 2>/dev/null)
      fi
      if [[ "$_ab_ok" -eq 1 ]]; then
        _pass "check5" "abort close: no plan content was published — ${target_branch} advanced from ${frozen_target:0:8} to ${target_head_now:0:8} only by this plan's own abort record in .aid-lifecycle/manifests/${PLAN_ID}.yaml"
      else
        _fail "check5" "abort close: ${target_branch} moved from ${frozen_target:0:8} to ${target_head_now:0:8} by commits that are NOT this plan's abort record — an aborted plan must publish no content"
      fi
    fi
  else
    if [[ "$merge_result" != "merged" || -z "$merge_commit" ]]; then
      _fail "check5" "the manifest records no published plan merge (plan_final_merge.result='${merge_result:-<none>}') — close is blocked until the merge or a recorded abort exists"
    elif ! git cat-file -e "${merge_commit}^{commit}" 2>/dev/null; then
      _fail "check5" "the recorded merge commit ${merge_commit} does not resolve in this repository — ancestry UNKNOWN, never treated as merged"
    elif [[ -z "$target_head_now" ]]; then
      _fail "check5" "the target branch ${target_branch} does not resolve — ancestry UNKNOWN"
    elif ! git merge-base --is-ancestor "$candidate" "$target_head_now" 2>/dev/null; then
      _fail "check5" "the candidate ${candidate:0:8} is NOT an ancestor of ${target_branch} (${target_head_now:0:8}) — the plan branch is not merged"
    elif [[ "$close_evidence_ok" -eq 1 ]] \
         && ! jq -e --arg mc "$merge_commit" --arg mt "$(git rev-parse "${merge_commit}^{tree}" 2>/dev/null)" \
              '.merge_commit == $mc and .merged_tree == $mt' <<< "$ce_receipt" >/dev/null 2>&1; then
      _fail "check5" "the durable close-evidence receipt's merge_commit/merged_tree does not match the manifest's recorded plan_final_merge (${merge_commit:0:8}) — refusing a receipt that disagrees with the merge it is supposed to attest to"
    else
      _pass "check5" "the plan merge ${merge_commit:0:8} is published and ${candidate:0:8} is an ancestor of ${target_branch}"
    fi
  fi

  # ── 5.7 the tag state matches project policy ───────────────────────────
  local version="" _relprep=""
  for f in "${run_dir}/release-prep.json" "${PLAN_STATE_DIR}/release-prep.json"; do
    [[ -s "$f" ]] || continue
    _relprep="$f"
    version="$(jq -r '.version // "none"' "$f" 2>/dev/null || echo none)"
    [[ -z "$version" || "$version" == "null" ]] && version="none"
    break
  done
  [[ -n "$version" ]] || version="none"
  # CP2 M3: the release record this check must not fail open on is the one the
  # merge transaction WRITES — plan_final_merge.tag ("none" or "vX.Y.Z"). An
  # absent release-prep.json is NOT that record: the merge path itself resolves a
  # missing file to "no bump" (_pfsm_release_prep_version), so demanding it here
  # would make every legitimate no-bump plan unclosable — which is exactly what
  # a first attempt at this fix did. Absence of the RECORDED tag status, and any
  # disagreement between it and a present release-prep.json, both block.
  local _rec_tag; _rec_tag="$(_pbm '.plan_boundary_manifest.plan_final_merge.tag')"
  if [[ "$CLOSE_MODE" == "abort" ]]; then
    _info "check5" "abort close: no tag assertion is made (nothing was released)"
  elif [[ -z "$_rec_tag" ]]; then
    _fail "check5" "the manifest records no tag status for the plan merge (plan_final_merge.tag is absent) — whether a tag was required cannot be established, so close is blocked rather than assumed"
  elif [[ -n "$_relprep" && "$version" != "none" && "$_rec_tag" != "v${version}" ]]; then
    _fail "check5" "the release record ${_relprep} prepared version ${version}, so tag v${version} was required, but the merge recorded tag status '${_rec_tag}' — the two disagree about what was released"
  elif [[ -n "$_relprep" && "$version" == "none" && "$_rec_tag" != "none" ]]; then
    _fail "check5" "the release record ${_relprep} prepared no version, but the merge recorded tag status '${_rec_tag}' — the two disagree about what was released"
  elif [[ "$_rec_tag" == "none" ]]; then
    _pass "check5" "the merge recorded no tag (no version bump for this plan) and no tag is required"
  elif [[ "$version" == "none" ]]; then
    # A tag was recorded with no release-prep.json to corroborate it: verify the
    # tag itself against the merge commit rather than trusting the record.
    version="${_rec_tag#v}"
    local tagged; tagged="$(git rev-parse --verify --quiet "refs/tags/${_rec_tag}^{commit}" 2>/dev/null || true)"
    if [[ -z "$tagged" ]]; then
      _fail "check5" "the merge recorded tag ${_rec_tag}, but that tag does not exist — the release record is incomplete"
    elif [[ -n "$merge_commit" && "$tagged" != "$merge_commit" ]]; then
      _fail "check5" "tag ${_rec_tag} points at ${tagged:0:8}, not at the plan merge ${merge_commit:0:8}"
    else
      _pass "check5" "tag ${_rec_tag} exists on the plan merge commit"
    fi
  else
    local tagged; tagged="$(git rev-parse --verify --quiet "refs/tags/v${version}^{commit}" 2>/dev/null || true)"
    if [[ -z "$tagged" ]]; then
      _fail "check5" "prepare-plan resolved version ${version} but tag v${version} does not exist — the release record is incomplete"
    elif [[ -n "$merge_commit" && "$tagged" != "$merge_commit" ]]; then
      _fail "check5" "tag v${version} points at ${tagged:0:8}, not at the plan merge ${merge_commit:0:8}"
    else
      _pass "check5" "tag v${version} exists on the plan merge commit"
    fi
  fi

  # ── 5.8 no merge is in progress ────────────────────────────────────────
  local gitdir; gitdir="$(git rev-parse --git-dir 2>/dev/null || echo .git)"
  if [[ -f "${gitdir}/MERGE_HEAD" ]]; then
    _fail "check5" "a merge is in progress (${gitdir}/MERGE_HEAD exists) — resolve or abort it before closing"
  else
    _pass "check5" "no MERGE_HEAD — no merge is in progress"
  fi

  # ── 5.9 no operation record is left at intent or git_applied ───────────
  local ops="${PLAN_STATE_DIR}/operations.jsonl"
  if [[ -f "$ops" ]]; then
    local stuck
    stuck="$(jq -rs '
      [ .[] | select(type == "object") ]
      | group_by(.op_id)
      | map({op_id: .[0].op_id, phase: (.[-1].phase // "")})
      | map(select(.phase == "intent" or .phase == "git_applied"))
      | map(.op_id + "@" + .phase) | join(", ")' "$ops" 2>/dev/null || true)"
    # CP2 M2: the exclusion used to drop EVERY `plan-close:*` record, so a prior
    # close attempt (a different attempt number, or a crashed abort close) stuck
    # at intent/git_applied was silently ignored by the guard whose whole job is
    # to notice exactly that. Only the operation in hand is excluded, by exact
    # op_id, and only when the caller names it.
    if [[ -n "$CLOSE_OP_ID" ]]; then
      stuck="$(printf '%s' "$stuck" | tr ',' '\n' \
        | grep -v -x -F -e " ${CLOSE_OP_ID}@intent" -e "${CLOSE_OP_ID}@intent" \
                        -e " ${CLOSE_OP_ID}@git_applied" -e "${CLOSE_OP_ID}@git_applied" \
        | paste -sd', ' - 2>/dev/null || true)"
    fi
    stuck="$(printf '%s' "$stuck" | sed 's/^ *//; s/ *$//')"
    if [[ -n "$stuck" ]]; then
      _fail "check5" "unfinished operation record(s) — a prior transaction never reached state_committed: ${stuck}"
    else
      _pass "check5" "no operation record is left at intent or git_applied"
    fi
  else
    _info "check5" "no operations.jsonl for ${PLAN_ID} — nothing to reconcile"
  fi

  # ── 5.10 no RELEVANT lock is currently HELD (owned-lock exception) ─────
  local lp held="" excl skip
  if [[ -d "$PLAN_STATE_DIR" ]]; then
    while IFS= read -r lp; do
      [[ -n "$lp" ]] || continue
      skip=0
      for excl in ${EXCLUDE_LOCKS[@]+"${EXCLUDE_LOCKS[@]}"}; do
        # Exact canonical path, NOT "any lock this process holds": a DIFFERENT
        # lock held by the same process must still block.
        [[ "$(readlink -f -- "$lp" 2>/dev/null || printf '%s' "$lp")" == \
           "$(readlink -f -- "$excl" 2>/dev/null || printf '%s' "$excl")" ]] && skip=1
      done
      [[ "$skip" -eq 1 ]] && continue
      if _lock_is_held "$lp"; then
        held="${held:+${held}, }${lp} (pid recorded in the sidecar: $(tr -d '\n' < "$lp" 2>/dev/null || echo unknown))"
      fi
    done < <(find "$PLAN_STATE_DIR" -maxdepth 1 -name '*.lock' 2>/dev/null | sort)
  fi
  if [[ -n "$held" ]]; then
    _fail "check5" "a relevant lock is still HELD by a live process: ${held} — close is blocked until it is released"
  else
    _pass "check5" "no relevant lock is held (existing .lock sidecars are expected; only a HELD lock blocks)"
  fi

  # ── 5.11 the .aid-lifecycle reconciliation ────────────────────────────
  local lc_manifest=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  if [[ ! -f "$lc_manifest" ]]; then
    # CP3 (2026-07-26): this branch used to key on the FILE, not the MODE, so
    # deleting the tracked manifest silently downgraded a plan_branch plan's
    # MANDATORY receipt to "legacy plan, close without one" — a plan declared
    # closed with no durable proof, and the exact inverse of AC7's "removing the
    # manifest blocks close". The escape hatch belongs to legacy plans only, and
    # `--plan-branch` is precisely the caller's assertion that this is not one.
    if [[ "$PLAN_BRANCH_MODE" -eq 1 ]]; then
      _fail "check5" "no lifecycle manifest at ${lc_manifest} for a plan-branch close — the receipt is MANDATORY for this mode, so its absence blocks rather than downgrading the close to the legacy no-receipt path"
    else
      _info "check5" "lifecycle_manifest_absent — ${lc_manifest} does not exist; this is a legacy-mode plan predating the lifecycle layer, so close completes with that reason recorded (aid-auto-pipeline.sh creates one for every plan made under the new model)"
    fi
  elif [[ "$CLOSE_MODE" == "abort" ]]; then
    _info "check5" "abort close: an aborted plan writes NO lifecycle receipt (aid_lifecycle_plan_close refuses while any required EPIC is undelivered, which is always true before a merge) — the manifest is marked aborted instead"
  else
    # Resolved against the TARGET BRANCH's copy of the lifecycle manifest, not
    # the worktree's: after the plan merge the delivery bindings live on the
    # target branch, while the worktree sits on plan/<plan_id> whose copy
    # predates them. Reading the worktree file here would report `active` for
    # every legitimately closable plan. Read-only — nothing is written.
    local lcs=""
    if declare -F aid_plan_closure_state >/dev/null 2>&1; then
      local _tb; _tb="$(aid_target_branch 2>/dev/null || echo main)"
      if aid_lc_manifest_ref_begin "$PLAN_ID" "$PROJECT_ROOT" "$_tb" 2>/dev/null; then
        lcs="$(aid_plan_closure_state "$PLAN_ID" "$PROJECT_ROOT" 2>/dev/null || true)"
        aid_lc_manifest_ref_end
      else
        lcs="$(aid_plan_closure_state "$PLAN_ID" "$PROJECT_ROOT" 2>/dev/null || true)"
      fi
    fi
    case "$lcs" in
      delivered-but-unreconciled|closing_pending_commit|closed)
        _pass "check5" "the lifecycle layer resolves to '${lcs}' — a receipt is writable (or already durable) for this plan" ;;
      active)
        _fail "check5" "the lifecycle layer resolves to 'active' — a required EPIC is not delivered + reviewed-accepted, so no durable closure proof can be written. Refusing to declare a plan closed with no receipt." ;;
      "")
        _fail "check5" "could not resolve the lifecycle closure state for ${PLAN_ID} (aid_plan_closure_state unavailable) — refusing to close on an unverified lifecycle layer" ;;
      *)
        _fail "check5" "the lifecycle layer resolves to '${lcs}' — not a closable state" ;;
    esac
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Aggregate
# ═══════════════════════════════════════════════════════════════════════

main() {
  check1_report_tracking
  check2_head_freshness
  check3_fsm_done_pending
  check4_queue_revalidate
  if [[ "$PLAN_BRANCH_MODE" -eq 1 ]]; then
    check5_plan_branch_boundary
  fi

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
