#!/usr/bin/env bash
# aid-test-adapter-shell-suite.sh — P072 Step 7.
#
# The fifth discovery adapter: standalone shell test suites, emitted as
# `sh:<relative-path-without-extension>` run units. That naming convention was
# already reserved by test-catalog.schema.json (the `run_unit_id` doc comment,
# "For shell suites: sh:<relative-path-without-extension>"), so this implements
# a contract the schema anticipated rather than inventing one.
#
# WHY THIS EXISTS: 43 files matching `test-*.sh` are real, CI-run suites in
# this repository and none of them were discoverable — the fixed adapter set
# was bats/package-script/declared-command, and the bats adapter globbed
# `*.bats` only. A repository-wide audit claim is not honest while a third of
# the portfolio is structurally invisible.
#
# CLASSIFICATION IS BY SHEBANG, NEVER BY FILENAME. Of those 43, seven carry
# `#!/usr/bin/env bats` and belong to the Bats adapter — `run-all-tests.sh:140`
# already dispatches them with `bats`, so calling them shell suites and running
# them with `bash` would break them. This adapter therefore claims only files
# whose shebang names bash/sh, and the Bats adapter claims the rest.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

# shell_suite_adapter_discover <project_root> [search_root] [skipped_out]
#   Emits one schema-valid run_unit per genuine shell suite on stdout.
#
#   Candidates it declines are written, with a reason, to <skipped_out> when
#   that third argument is given. A skip is RECORDED, never silent: a count
#   that quietly drops files is the failure this whole capability exists to
#   remove, and the two adapters' counts must reconcile without subtraction.
#
#   The ledger is a FILE, not a variable. Every caller invokes this through
#   command substitution (`units="$(shell_suite_adapter_discover …)"`), which
#   runs it in a subshell — a variable set here would be discarded before the
#   caller could read it, making the ledger unreachable by construction. The
#   adapter's own test suite caught exactly that.
shell_suite_adapter_discover() {
  local project_root="$1" search_root="${2:-$1}" skipped_out="${3:-}"
  # The ledger is REQUIRED. An optional one is an optional record, and a
  # caller that omits it loses every skip silently — which is the exact
  # failure this adapter exists to prevent, just relocated.
  [[ -n "$skipped_out" ]] || {
    echo "shell_suite_adapter_discover: a skipped-ledger path is required (3rd argument) — a skip that is not recorded is a file silently dropped from the portfolio" >&2
    return 2
  }
  local ndjson_file skipped_file
  ndjson_file="$(adapter_ndjson_start)" || return 1
  skipped_file="$(mktemp)" || { rm -f "$ndjson_file"; return 1; }

  local file rel rel_noext run_unit_id kind
  while IFS= read -r -d '' file; do
    rel="${file#"${project_root%/}"/}"

    kind="$(adapter_shebang_runner "$file")"

    case "$kind" in
      bats)
        # Owned by the Bats adapter. Recorded so the two adapters' counts can
        # be reconciled without subtraction.
        _shell_suite_record_skip "$skipped_file" "$rel" "claimed_by_bats_adapter"
        continue
        ;;
      none)
        # A helper that defines functions and runs nothing. Excluding it is
        # what keeps the portfolio count honest rather than inflated.
        _shell_suite_record_skip "$skipped_file" "$rel" "no_shell_shebang"
        continue
        ;;
    esac

    rel_noext="${rel%.sh}"
    run_unit_id="sh:${rel_noext}"

    if ! _shell_suite_id_is_safe "$run_unit_id"; then
      rm -f "$ndjson_file" "$skipped_file"
      echo "shell_suite_adapter_discover: refusing '$rel' — its derived run_unit_id '$run_unit_id' contains characters outside the stable-id charset; a mangled id silently breaks disposition reconciliation" >&2
      return 1
    fi

    local rel_escaped command_json source_paths_json unit_json
    rel_escaped="$(adapter_json_escape "$rel")"
    # `bash <path>` — the invocation run-all-tests.sh actually uses for these,
    # so a measured command is the command the project really runs. Sorted-key
    # canonical ("argv" < "type"), matching `jq -cS`.
    command_json='{"argv":["bash","'"$rel_escaped"'"],"type":"argv"}'
    source_paths_json='["'"$rel_escaped"'"]'

    # No test_cases: a shell suite has no statically enumerable case list the
    # way a Bats file does. An empty array is the honest answer; inventing
    # per-case entries from echo lines would be a guess presented as structure.
    unit_json="$(adapter_run_unit_json "$run_unit_id" "sh" "$command_json" '[]' \
      "$source_paths_json" "low" '["sh"]')" || {
      echo "shell_suite_adapter_discover: fingerprint computation failed for $rel" >&2
      rm -f "$ndjson_file" "$skipped_file"
      return 1
    }
    adapter_ndjson_append "$ndjson_file" "$unit_json"
  done < <(_shell_suite_candidates "$search_root")

  # Symlinked candidates: excluded, but named.
  while IFS= read -r -d '' file; do
    _shell_suite_record_skip "$skipped_file" "${file#"${project_root%/}"/}" "symlink_not_followed"
  done < <(_shell_suite_symlink_candidates "$search_root")

  # The ledger never joins the NDJSON stream either: adapter_ndjson_finish
  # turns that stream into one array, so a `{"skipped":…}` record would sit
  # among the run units and fail the inventory schema.
  jq -sc '.' < "$skipped_file" > "$skipped_out" \
    || { rm -f "$ndjson_file" "$skipped_file"; return 1; }
  rm -f "$skipped_file"

  adapter_ndjson_finish "$ndjson_file"
}

# _shell_suite_record_skip <ledger_file> <path> <reason>
#   One JSON object per line. NOT tab-separated: a path containing a tab would
#   split into the wrong fields, mis-attributing the reason to a truncated
#   path — a corrupt ledger is worse than none, because it looks complete.
_shell_suite_record_skip() {
  jq -nc --arg p "$2" --arg r "$3" '{path:$p, reason:$r}' >> "$1"
}

# _shell_suite_candidates <search_root> — NUL-delimited `test-*.sh` files,
# excluding vendored trees and fixture directories (a fixture script is input
# to a test, not a suite).
#
# `.aid-worktrees/` is excluded because AID itself creates worktrees INSIDE the
# repository it is working on (plan and frozen-CP3 trees). Those are copies of
# the same suites belonging to another session, and their dotted paths produce
# ids outside the stable-id charset — so a concurrent session's worktree turned
# discovery into a hard refusal for the whole portfolio. Found 2026-08-11 by a
# red T1 during a release, where the only cause was that a second window had a
# plan checked out.
#
# `-type f` deliberately excludes symlinks: a symlinked suite would otherwise
# be discovered twice, once under each name, and the two ids would disagree
# about which file the portfolio contains. Excluded symlinks are RECORDED by
# the caller loop below rather than dropped in silence.
_shell_suite_candidates() {
  local search_root="$1"
  # EVERY dot-directory below the root is pruned, not a hand-listed few. The
  # 2026-08-11 fix named `.aid-worktrees/` — the path AID's own plan worktrees
  # use — and the very next occurrence came from `.claude/worktrees/plan-P083`,
  # which the Claude Code harness creates and which this list had never heard
  # of. Same failure, different dotted parent: a nested checkout's copies of
  # these suites produce ids outside the stable-id charset, and discovery
  # refuses for the whole portfolio.
  #
  # `-mindepth 1` matters: without it a search_root whose OWN basename starts
  # with a dot (running the audit from inside `.aid-worktrees/plan-P0xx`, which
  # is a supported thing to do) would prune itself and discover nothing.
  find "$search_root" -mindepth 1 \
    \( -type d -name '.*' -prune \) -o \
    \( -type f -name 'test-*.sh' \
       -not -path '*/node_modules/*' \
       -not -path '*/fixtures/*' \
       -print0 \) | sort -z
}

# _shell_suite_symlink_candidates <search_root> — symlinked `test-*.sh` files,
# recorded so their exclusion is visible in the ledger.
_shell_suite_symlink_candidates() {
  local search_root="$1"
  find "$search_root" -type l -name 'test-*.sh' \
    -not -path '*/node_modules/*' \
    -not -path '*/fixtures/*' \
    -not -path '*/.aid-worktrees/*' \
    -not -path '*/.git/*' \
    -print0 | sort -z
}

# _shell_suite_id_is_safe <run_unit_id> — the same charset every other stable
# id in this system uses. A path with a character outside it would produce an
# id the reconciliation cannot match.
_shell_suite_id_is_safe() {
  [[ "$1" =~ ^sh:[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]
}
