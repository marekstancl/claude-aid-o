#!/usr/bin/env bash
# aid-test-resource-map.sh — P072 Step 14.
#
# What resources does a run unit touch, and is each one private to a test,
# private to a run, or shared with everything else? This reads source. It runs
# nothing.
#
# WHY IT IS NOT A GREP
#   The first P066 audit reasoned about parallel safety from pattern matches
#   and produced false lock-positives: a file mentioning the word "lock" was
#   called unsafe, and a file whose isolation came from a helper it sourced was
#   called unknown because the helper's `mktemp` was in another file. Both
#   errors have the same shape — the evidence was in a file the matcher never
#   opened. So this follows `source`, `.` and Bats `load` directives up to a
#   recorded depth cap, and every entry carries the `file:line` that justifies
#   it.
#
# THE DIRECTION THAT MATTERS
#   Downstream, only `per-test` and `per-run` units may share a parallel pool.
#   So the two errors are not symmetric:
#
#     a false PRIVATE (per-test/per-run) puts a genuinely shared resource into
#       a concurrent pool — corruption;
#     a false SHARED keeps a unit sequential — waste;
#     `unknown` is fail-closed and costs exactly what `shared` costs.
#
#   Every rule below resolves toward `unknown` when it cannot decide, and the
#   working directory NEVER makes an explicitly anchored path private. Four
#   findings from an adversarial review are pinned into the code for that
#   reason: `git -C`/`GIT_DIR` override the working directory; an absolute or
#   `$VAR`-anchored path does not depend on it at all; a `cd` this cannot
#   resolve makes the directory unknown rather than leaving the last known
#   value standing; and a helper that exists but was never read caps the unit.
#
# WHAT IT HONESTLY CANNOT DECIDE
#   Shell is not statically analysable in general. Paths assembled from
#   variables, helpers reached through computed paths, `eval`, and dynamic
#   dispatch are beyond it. The guarantee is narrower than "everything
#   unreadable becomes unknown": it is that the constructs this DOES recognise
#   resolve toward `unknown` rather than toward private, and that a dependency
#   it could not read caps the whole unit. A construct it does not recognise at
#   all can still be missed — which is why a pilot run, not this map alone, is
#   what promotes a unit into a pool.
#
# Exit codes: 0 ok · 2 usage · 3 unreadable catalog or unit · 4 unreadable source

set -euo pipefail

_die() { echo "aid-test-resource-map.sh: $2" >&2; exit "$1"; }

run_unit_id="" catalog_path="" project_root="" depth_cap=3 out_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-unit-id)  [[ $# -ge 2 ]] || _die 2 "--run-unit-id requires a value"; run_unit_id="$2"; shift 2 ;;
    --catalog)      [[ $# -ge 2 ]] || _die 2 "--catalog requires a value"; catalog_path="$2"; shift 2 ;;
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --depth-cap)    [[ $# -ge 2 ]] || _die 2 "--depth-cap requires a value"; depth_cap="$2"; shift 2 ;;
    --output)       [[ $# -ge 2 ]] || _die 2 "--output requires a value"; out_path="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$run_unit_id" ]] || _die 2 "--run-unit-id is required"
[[ -n "$catalog_path" && -f "$catalog_path" ]] || _die 2 "--catalog is required and must exist"
[[ -n "$project_root" && -d "$project_root" ]] || _die 2 "--project-root is required and must exist"
[[ "$depth_cap" =~ ^[0-9]+$ ]] || _die 2 "--depth-cap must be a non-negative integer (got '$depth_cap')"

project_canon="$(cd "$project_root" && pwd -P)"

unit_json="$(yq -o=json '.' "$catalog_path" \
  | jq -c --arg id "$run_unit_id" '.run_units[] | select(.run_unit_id == $id)')" \
  || _die 3 "could not read the catalog"
[[ -n "$unit_json" ]] || _die 3 "run unit '$run_unit_id' is not in the catalog"

mapfile -t own_sources < <(jq -r '(.source_paths // [])[]' <<<"$unit_json")
[[ "${#own_sources[@]}" -gt 0 ]] \
  || _die 3 "run unit '$run_unit_id' declares no source_paths — there is nothing to read, and an empty map would read as 'touches nothing'"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
: > "$work/resources.jsonl"
: > "$work/unresolved.jsonl"
: > "$work/files.txt"
: > "$work/funcdefs.txt"    # name<TAB>file<TAB>start<TAB>end
: > "$work/calls.txt"       # caller-scope<TAB>callee
: > "$work/pertest_fns.txt"
: > "$work/cdfns.txt"       # name<TAB>(temp|elsewhere|unknown)

_rel() {
  local p="$1"
  case "$p" in
    "$project_canon"/*) printf '%s' "${p#"$project_canon"/}" ;;
    *) printf '%s' "$p" ;;
  esac
}

# Brace counting without subprocesses. The first cut shelled out six times per
# source line, which pushed a 900-line suite past a two-minute budget — a
# static reader that costs more than the test it inspects will not get run.
_open=0; _close=0
_braces() {
  local t="${1//[^\{]/}"; _open=${#t}
  t="${1//[^\}]/}"; _close=${#t}
}

# ─── Temp-rootedness ────────────────────────────────────────────────────────
temp_vars=""
_is_temp_expr() {
  local e="$1" v
  for v in $temp_vars; do
    [[ "$e" == *"\$$v"* || "$e" == *"\${$v"* ]] && return 0
  done
  [[ "$e" == *'$TEST_TMPDIR'*       || "$e" == *'${TEST_TMPDIR'*       ]] && return 0
  [[ "$e" == *'$TEST_PROJECT_ROOT'* || "$e" == *'${TEST_PROJECT_ROOT'* ]] && return 0
  [[ "$e" == *'$TEST_EVIDENCE_DIR'* || "$e" == *'${TEST_EVIDENCE_DIR'* ]] && return 0
  [[ "$e" == *'$BATS_TEST_TMPDIR'*  || "$e" == *'${BATS_TEST_TMPDIR'*  ]] && return 0
  [[ "$e" == *'$BATS_FILE_TMPDIR'*  || "$e" == *'${BATS_FILE_TMPDIR'*  ]] && return 0
  [[ "$e" == *'mktemp'* ]] && return 0
  return 1
}

# An operand that names its own root — absolute, or anchored to a variable that
# is not a temp root. The working directory is irrelevant to it, so `cwd` must
# never be allowed to make it private. This is the review finding that
# `printf x > "$BATS_TEST_DIRNAME/../.aid-o/state"` inside a temp-rooted test
# was being reported as per-test.
_is_anchored_elsewhere() {
  local e="$1"
  _is_temp_expr "$e" && return 1
  [[ "$e" == /* ]] && return 0
  [[ "$e" =~ ^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/ ]] && return 0
  return 1
}

# ─── Pass 1: locate files and function definitions ──────────────────────────
_record_unresolved() {
  jq -nc --arg d "$1" --arg loc "$2" --arg why "$3" \
    '{directive:$d, location:$loc, reason:$why}' >> "$work/unresolved.jsonl"
}

# Path variables assigned in the file being read, so that
# `HELPER="$BATS_TEST_DIRNAME/helpers.bash"` followed by `source "$HELPER"` is
# a directive this can FOLLOW rather than one it must give up on. The first
# cut gave up on all of them, which capped 28 of this repository's 74 bats
# units at `unknown` — technically fail-closed, practically useless, and
# needlessly so: the assignment is right there in the same file.
declare -A path_vars=()

_expand_path_expr() {          # <expr> <dir-of-current-file> -> expanded or ""
  local e="$1" dir="$2" prev=""
  local i=0
  while [[ "$e" == *'$'* && "$i" -lt 8 && "$e" != "$prev" ]]; do
    prev="$e"; i=$(( i + 1 ))
    e="${e//\$\{BATS_TEST_DIRNAME\}/$dir}"; e="${e//\$BATS_TEST_DIRNAME/$dir}"
    e="${e//\$\{SCRIPT_DIR\}/$dir}";        e="${e//\$SCRIPT_DIR/$dir}"
    e="${e//\$\{BASH_SOURCE\[0\]%/*\}/$dir}"
    # `X="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"` is how almost every suite
    # here names the plugin root. Leaving it unexpanded meant every helper
    # reached through X was unreadable, and the unit capped at `unknown` —
    # fail-closed, but for no reason: the path is right there.
    if [[ "$e" =~ \$\(cd[[:space:]]+\"?([^\"\&\)]+)\"?[[:space:]]*\&\&[[:space:]]*pwd[[:space:]]*\) ]]; then
      local _inner="${BASH_REMATCH[1]}"
      _inner="${_inner//\$\{BATS_TEST_DIRNAME\}/$dir}"; _inner="${_inner//\$BATS_TEST_DIRNAME/$dir}"
      _inner="${_inner//\$\{SCRIPT_DIR\}/$dir}"; _inner="${_inner//\$SCRIPT_DIR/$dir}"
      _inner="${_inner%"${_inner##*[![:space:]]}"}"
      if [[ "$_inner" != *'$'* ]] && [[ -d "$_inner" ]]; then
        local _abs; _abs="$(cd "$_inner" 2>/dev/null && pwd -P || true)"
        [[ -n "$_abs" ]] && e="${e/${BASH_REMATCH[0]}/$_abs}"
      fi
    fi
    local name
    for name in "${!path_vars[@]}"; do
      e="${e//\$\{$name\}/${path_vars[$name]}}"
      e="${e//\$$name/${path_vars[$name]}}"
    done
  done
  [[ "$e" == *'$'* ]] && { printf ''; return 1; }
  printf '%s' "$e"
}

_collect_file() {
  local file="$1" depth="$2"
  local rel; rel="$(_rel "$file")"
  if grep -qxF "$rel" "$work/files.txt" 2>/dev/null; then return 0; fi
  printf '%s\n' "$rel" >> "$work/files.txt"
  [[ -r "$file" ]] || _die 4 "cannot read source file '$file'"

  local lineno=0 line code fn="" fn_start=0 fn_depth=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$(( lineno + 1 ))
    code="${line%%#*}"

    if [[ -z "$fn" ]]; then
      if [[ "$code" =~ ^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*\(\)[[:space:]]*\{ ]]; then
        fn="${BASH_REMATCH[2]}"; fn_start="$lineno"
        # A one-line definition closes on the same line. Skipping the rest of
        # the line after opening a block was how `setup() { cd "$TMP"; }` — the
        # single most common shape in this repository — went entirely unread.
        _braces "$code"; fn_depth=$(( _open - _close ))
        if [[ "$fn_depth" -le 0 ]]; then
          printf '%s\t%s\t%s\t%s\n' "$fn" "$rel" "$fn_start" "$lineno" >> "$work/funcdefs.txt"
          fn=""
        fi
      fi
    else
      _braces "$code"; fn_depth=$(( fn_depth + _open - _close ))
      if [[ "$fn_depth" -le 0 ]]; then
        printf '%s\t%s\t%s\t%s\n' "$fn" "$rel" "$fn_start" "$lineno" >> "$work/funcdefs.txt"
        fn=""
      fi
    fi

    # Remember simple assignments, so a later `source "$VAR"` is followable.
    # The value is taken as the rest of the line and unquoted afterwards. A
    # character class that stopped at the first quote could not read
    # `X="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"` — the single most common
    # way a suite names its plugin root — because the value contains quotes.
    if [[ "$code" =~ ^[[:space:]]*(local[[:space:]]+|export[[:space:]]+|readonly[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
      local _vn="${BASH_REMATCH[2]}" _vv="${BASH_REMATCH[3]}"
      _vv="${_vv%"${_vv##*[![:space:]]}"}"
      [[ "$_vv" == \"*\" ]] && _vv="${_vv:1:${#_vv}-2}"
      if [[ "$_vv" == */* || "$_vv" == *'$'* ]]; then
        local _exp; _exp="$(_expand_path_expr "$_vv" "$(dirname "$file")" || true)"
        [[ -n "$_exp" ]] && path_vars["$_vn"]="$_exp"
      fi
    fi

    if [[ "$code" =~ ^[[:space:]]*(source|\.|load)[[:space:]]+(.+)$ ]]; then
      local directive="${BASH_REMATCH[2]}"
      directive="${directive%%[[:space:]]*}"
      directive="${directive//\"/}"; directive="${directive//\'/}"
      local target=""
      case "$directive" in
        /*) target="$directive" ;;
        *\$*)
          local expanded; expanded="$(_expand_path_expr "$directive" "$(dirname "$file")" || true)"
          if [[ -z "$expanded" ]]; then
            _record_unresolved "$directive" "$rel:$lineno" "path is computed from variables this cannot expand"
          else
            target="$expanded"
          fi
          ;;
        *) target="$(dirname "$file")/$directive" ;;
      esac
      if [[ -n "$target" ]]; then
        if [[ ! -f "$target" && -f "${target}.bash" ]]; then target="${target}.bash"; fi
        if [[ -f "$target" ]]; then
          if [[ "$depth" -lt "$depth_cap" ]]; then
            _collect_file "$target" $(( depth + 1 ))
          else
            # The helper EXISTS; it simply was not read. Omitting it silently
            # reported a unit as clean on the strength of a file nobody
            # opened — the same error as the audit this replaces.
            _record_unresolved "$directive" "$rel:$lineno" \
              "helper exists but lies beyond the depth cap of ${depth_cap}, so its contents were never read"
          fi
        else
          _record_unresolved "$directive" "$rel:$lineno" "target does not exist"
        fi
      fi
    fi
  done < "$file"
  return 0
}

for src in "${own_sources[@]}"; do
  abs="$src"; [[ "$abs" = /* ]] || abs="${project_canon}/${src}"
  [[ -f "$abs" ]] || _die 4 "declared source path '$src' does not exist — a map built over a missing file would describe nothing"
  _collect_file "$abs" 0
done

all_fn_names="$(cut -f1 "$work/funcdefs.txt" 2>/dev/null | sort -u || true)"

# ─── Block recognition, shared by every later pass ──────────────────────────
_blk=""
_block_open() {
  _blk=""
  if [[ "$1" =~ ^[[:space:]]*setup(_file)?\(\)[[:space:]]*\{ ]]; then _blk="per-test"; return 0; fi
  if [[ "$1" =~ ^[[:space:]]*@test[[:space:]] ]]; then _blk="per-test"; return 0; fi
  if [[ "$1" =~ ^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*\(\)[[:space:]]*\{ ]]; then
    _blk="fn:${BASH_REMATCH[2]}"
  fi
  return 0
}

# ─── Pass 2: call graph, and which functions are per-test ──────────────────
# A set, so a line costs one lookup per WORD rather than one regex per known
# function. The loop-over-every-function form was O(lines x functions) and
# pushed the two largest suites past a two-minute budget once variable
# expansion started pulling in the production libraries they source.
declare -A fn_set=()
while IFS= read -r _n; do [[ -n "$_n" ]] && fn_set["$_n"]=1; done <<< "$all_fn_names"

_record_calls() {
  local rel="$1"; local file="${project_canon}/${rel}"
  [[ -f "$file" ]] || file="$rel"
  [[ "${#fn_set[@]}" -gt 0 ]] || return 0

  local line code scope="per-run" depth=0 w
  while IFS= read -r line || [[ -n "$line" ]]; do
    code="${line%%#*}"
    if [[ "$scope" == "per-run" ]]; then
      _block_open "$code"
      if [[ -n "$_blk" ]]; then
        scope="$_blk"; _braces "$code"; depth=$(( _open - _close ))
      fi
    else
      _braces "$code"; depth=$(( depth + _open - _close ))
    fi

    if [[ "$scope" != "per-run" ]]; then
      for w in $code; do
        w="${w%%[^A-Za-z0-9_-]*}"
        [[ -z "$w" ]] && continue
        if [[ -n "${fn_set[$w]:-}" ]] && [[ ! "$code" =~ $w[[:space:]]*\(\) ]]; then
          printf '%s\t%s\n' "$scope" "$w" >> "$work/calls.txt"
        fi
      done
      [[ "$depth" -le 0 ]] && scope="per-run"
    fi
  done < "$file"
  return 0
}

while IFS= read -r rel; do _record_calls "$rel"; done < "$work/files.txt"

# A function is per-test when it is called from a per-test block, or from a
# function that is itself per-test. Computed to a fixed point: a two-level
# helper chain is ordinary and must not lose the guarantee halfway down.
while :; do
  before="$(wc -l < "$work/pertest_fns.txt")"
  while IFS=$'\t' read -r scope callee; do
    [[ -z "$callee" ]] && continue
    promote=0
    if [[ "$scope" == "per-test" ]]; then
      promote=1
    elif [[ "$scope" == fn:* ]] && grep -qxF "${scope#fn:}" "$work/pertest_fns.txt" 2>/dev/null; then
      promote=1
    fi
    if [[ "$promote" -eq 1 ]] && ! grep -qxF "$callee" "$work/pertest_fns.txt" 2>/dev/null; then
      printf '%s\n' "$callee" >> "$work/pertest_fns.txt"
    fi
  done < "$work/calls.txt"
  after="$(wc -l < "$work/pertest_fns.txt")"
  [[ "$after" -eq "$before" ]] && break
done

# ─── Pass 2b: where does a block LEAVE the working directory? ──────────────
#
# The LAST `cd` wins, not the first. A setup that cd'd into a temp root and
# then `cd -` back was leaving every later resource marked private. `cd -`, a
# conditional `cd`, and a `cd` to an unresolvable path all end in `unknown`,
# which is fail-closed.
#
# Values: temp | elsewhere | unknown | none
_final_cd_of_range() {
  local file="$1" start="$2" end="$3"
  local verdict="none" line code dest
  while IFS= read -r line; do
    code="${line%%#*}"
    if [[ "$code" =~ (^|[[:space:]\;\&\|\{])cd[[:space:]]+([^\;\&\|]+) ]]; then
      dest="${BASH_REMATCH[2]}"; dest="${dest%%[[:space:]]*}"
      dest="${dest//\"/}"; dest="${dest//\'/}"
      if [[ "$dest" == "-" ]]; then verdict="unknown"
      elif [[ "$code" =~ (\|\||\&\&) ]]; then verdict="unknown"
      elif _is_temp_expr "$dest"; then verdict="temp"
      elif [[ "$dest" != *'$'* ]]; then verdict="elsewhere"
      else verdict="unknown"; fi
    fi
  done < <(sed -n "${start},${end}p" "$file" 2>/dev/null)
  printf '%s' "$verdict"
}

while IFS=$'\t' read -r fname ffile fstart fend; do
  [[ -z "$fname" ]] && continue
  fpath="${project_canon}/${ffile}"; [[ -f "$fpath" ]] || fpath="$ffile"
  v="$(_final_cd_of_range "$fpath" "$fstart" "$fend")"
  [[ "$v" == "none" ]] || printf '%s\t%s\n' "$fname" "$v" >> "$work/cdfns.txt"
done < "$work/funcdefs.txt"

# Per FILE, never globally: Bats does not run one file's setup before another
# file's tests, so one suite's isolation must not be credited to a sibling.
_setup_cwd_for_file() {
  local rel="$1"; local file="${project_canon}/${rel}"
  [[ -f "$file" ]] || file="$rel"
  local start="" end="" fname ffile fstart fend
  while IFS=$'\t' read -r fname ffile fstart fend; do
    if [[ "$fname" == "setup" && "$ffile" == "$rel" ]]; then start="$fstart"; end="$fend"; fi
  done < "$work/funcdefs.txt"
  [[ -n "$start" ]] || { printf 'none'; return 0; }

  local v; v="$(_final_cd_of_range "$file" "$start" "$end")"
  if [[ "$v" == "none" ]]; then
    # setup() may establish the directory through a helper instead.
    local line code name hv
    while IFS= read -r line; do
      code="${line%%#*}"
      while IFS=$'\t' read -r name hv; do
        [[ -z "$name" ]] && continue
        [[ "$code" == *"$name"* ]] && v="$hv"
      done < "$work/cdfns.txt"
    done < <(sed -n "${start},${end}p" "$file" 2>/dev/null)
  fi
  printf '%s' "${v:-none}"
}

# ─── Pass 3: emit ───────────────────────────────────────────────────────────
current_via=""
_emit() {
  jq -nc --arg k "$1" --arg n "$2" --arg d "$3" --arg loc "$4:$5" --arg via "$current_via" \
    '{kind:$k, namespace:$n, detail:$d, location:$loc}
     + (if $via == "" then {} else {via:$via} end)' >> "$work/resources.jsonl"
}

# Namespace for a resource whose privacy depends on the working directory.
_ns_for_cwd() {
  case "$1" in
    temp) printf '%s' "$2" ;;
    elsewhere) printf 'shared' ;;
    *) printf 'unknown' ;;
  esac
}

_scan_for_resources() {
  local rel="$1"; local file="${project_canon}/${rel}"
  [[ -f "$file" ]] || file="$rel"
  local is_own=0 s
  for s in "${own_sources[@]}"; do [[ "$rel" == "$s" ]] && is_own=1; done
  current_via=""
  [[ "$is_own" -eq 0 ]] && current_via="$(basename "$rel")"

  local setup_cwd; setup_cwd="$(_setup_cwd_for_file "$rel")"

  local lineno=0 line code scope="per-run" depth=0 blk_kind=""
  local cwd="elsewhere"   # at a file's top level the runner's directory applies
  temp_vars=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$(( lineno + 1 ))
    code="${line%%#*}"

    if [[ -z "$blk_kind" ]]; then
      _block_open "$code"
      if [[ -n "$_blk" ]]; then
        blk_kind="$_blk"; temp_vars=""
        if [[ "$_blk" == "per-test" ]]; then
          scope="per-test"
          if [[ "$code" =~ ^[[:space:]]*@test[[:space:]] ]]; then
            case "$setup_cwd" in
              temp) cwd="temp" ;;
              elsewhere|none) cwd="elsewhere" ;;
              *) cwd="unknown" ;;
            esac
          else
            cwd="elsewhere"     # a setup body starts where the runner started
          fi
        else
          local fname="${_blk#fn:}"
          scope="per-run"
          if grep -qxF "$fname" "$work/pertest_fns.txt" 2>/dev/null; then scope="per-test"; fi
          # A function's working directory is the caller's, and this cannot
          # see the caller.
          cwd="unknown"
        fi
        _braces "$code"; depth=$(( _open - _close ))
      fi
    else
      _braces "$code"; depth=$(( depth + _open - _close ))
    fi

    if [[ -n "${code// }" ]]; then
      if [[ "$code" =~ ^[[:space:]]*(local[[:space:]]+|export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
        if _is_temp_expr "${BASH_REMATCH[3]}"; then temp_vars="$temp_vars ${BASH_REMATCH[2]}"; fi
      fi

      # ── working directory ──────────────────────────────────────────────
      if [[ "$code" =~ (^|[[:space:]\;\&\|\{])cd[[:space:]]+([^\;\&\|]+) ]]; then
        local dest="${BASH_REMATCH[2]}"; dest="${dest%%[[:space:]]*}"
        dest="${dest//\"/}"; dest="${dest//\'/}"
        if [[ "$dest" == "-" ]]; then
          cwd="unknown"
          _emit "working_dir" "unknown" "cd - returns somewhere this cannot determine" "$rel" "$lineno"
        elif [[ "$code" =~ (\|\||\&\&) ]]; then
          cwd="unknown"
          _emit "working_dir" "unknown" "conditional cd — whether it took effect is not statically decidable" "$rel" "$lineno"
        elif _is_temp_expr "$dest"; then
          cwd="temp"
          _emit "working_dir" "$scope" "cd into a temp root" "$rel" "$lineno"
        elif [[ "$dest" != *'$'* ]]; then
          cwd="elsewhere"
          _emit "working_dir" "per-run" "cd to a literal path: $dest" "$rel" "$lineno"
        else
          cwd="unknown"
          _emit "working_dir" "unknown" "cd to a path this cannot resolve: $dest" "$rel" "$lineno"
        fi
      fi

      [[ "$code" == *mktemp* ]] && _emit "temp_path" "$scope" "mktemp" "$rel" "$lineno"

      # ── git ────────────────────────────────────────────────────────────
      if [[ "$code" =~ (^|[^[:alnum:]_])git[[:space:]] || "$code" == *GIT_DIR=* || "$code" == *GIT_WORK_TREE=* ]]; then
        # An explicit repository selector decides regardless of the working
        # directory: `git -C <real repo>` inside a temp-rooted test mutates the
        # real repository, and was being reported as private.
        local selector="" git_ns=""
        if   [[ "$code" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then selector="${BASH_REMATCH[1]}"
        elif [[ "$code" =~ --git-dir=([^[:space:]]+)   ]]; then selector="${BASH_REMATCH[1]}"
        elif [[ "$code" =~ GIT_DIR=([^[:space:]]+)     ]]; then selector="${BASH_REMATCH[1]}"
        elif [[ "$code" =~ GIT_WORK_TREE=([^[:space:]]+) ]]; then selector="${BASH_REMATCH[1]}"
        fi

        if [[ -n "$selector" ]]; then
          if _is_temp_expr "$selector"; then git_ns="$scope"
          elif [[ "$selector" == *'$'* ]]; then git_ns="unknown"
          else git_ns="shared"; fi
        else
          git_ns="$(_ns_for_cwd "$cwd" "$scope")"
        fi

        if [[ "$code" =~ git[[:space:]]+worktree ]]; then
          if [[ -n "$selector" ]] && _is_temp_expr "$selector"; then
            _emit "git_worktree" "$scope" "git worktree in a temp repository" "$rel" "$lineno"
          else
            # A worktree registers itself in the repository it is created
            # from, so a temp destination does not make it private.
            _emit "git_worktree" "shared" "git worktree add — registers in the surrounding repository's object store" "$rel" "$lineno"
          fi
        elif [[ "$code" =~ git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(commit|checkout|reset|merge|branch|tag|stash|add|rm|push|clean|init|config) ]]; then
          case "$git_ns" in
            shared)  _emit "git_repo" "shared"  "git mutation against a repository outside any temp root" "$rel" "$lineno" ;;
            unknown) _emit "git_repo" "unknown" "git mutation whose target repository this cannot resolve" "$rel" "$lineno" ;;
            *)       _emit "git_repo" "$git_ns" "git against a temp root" "$rel" "$lineno" ;;
          esac
        fi
      fi

      # ── locks ──────────────────────────────────────────────────────────
      # What is invoked, not what is mentioned. A test NAMED "...lock..." is
      # not a lock user; `flock` is. That is the literal P066 false positive.
      if [[ "$code" =~ (^|[^[:alnum:]_])flock([[:space:]]|$) ]]; then
        _emit "lock" "shared" "flock" "$rel" "$lineno"
      fi

      if [[ "$code" =~ (localhost|127\.0\.0\.1):([0-9]{2,5}) ]]; then
        _emit "port" "shared" "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}" "$rel" "$lineno"
      fi

      # ── writes ─────────────────────────────────────────────────────────
      # ANY write, not only ones landing under a few hard-coded repository
      # prefixes: a write to `$HOME/.cache/...` or `/tmp/shared-state`
      # produced no entry at all, so the conflict was invisible to the pooling
      # decision that reads this map.
      if [[ "$code" =~ (^|[[:space:]])(mkdir|touch|cp|mv|rm|tee|ln)[[:space:]] || "$code" == *'>'* ]]; then
        local target_expr=""
        if [[ "$code" =~ \>\>?[[:space:]]*\"?([^[:space:]\"\;\&\|\(\)]+) ]]; then
          target_expr="${BASH_REMATCH[1]}"
        elif [[ "$code" =~ (mkdir|touch|cp|mv|rm|tee|ln)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*\"?([^[:space:]\"\;\&\|\(\)]+) ]]; then
          target_expr="${BASH_REMATCH[3]}"
        fi

        if [[ -n "$target_expr" && "$target_expr" != "/dev/null" && "$target_expr" != /dev/* ]]; then
          local kind="fixed_path"
          [[ "$target_expr" == *".aid-o"* ]] && kind="aid_state"
          [[ "$target_expr" == *".cache"* || "$target_expr" == *'$HOME'* ]] && kind="cache"

          if _is_temp_expr "$target_expr"; then
            _emit "$kind" "$scope" "$target_expr (under a temp root)" "$rel" "$lineno"
          elif _is_anchored_elsewhere "$target_expr"; then
            if [[ "$target_expr" == *'$'* ]]; then
              _emit "$kind" "unknown" "$target_expr (anchored to a variable this cannot resolve)" "$rel" "$lineno"
            else
              _emit "$kind" "shared" "$target_expr" "$rel" "$lineno"
            fi
          else
            local ns; ns="$(_ns_for_cwd "$cwd" "$scope")"
            case "$ns" in
              shared)  _emit "$kind" "shared"  "$target_expr (relative to a directory outside any temp root)" "$rel" "$lineno" ;;
              unknown) _emit "$kind" "unknown" "$target_expr (relative to a directory this cannot resolve)" "$rel" "$lineno" ;;
              *)       _emit "$kind" "$ns" "$target_expr (under a temp root)" "$rel" "$lineno" ;;
            esac
          fi
        fi
      fi
    fi

    if [[ -n "$blk_kind" && "$depth" -le 0 ]]; then
      blk_kind=""; scope="per-run"; cwd="elsewhere"; temp_vars=""
    fi
  done < "$file"
  current_via=""
  return 0
}

while IFS= read -r rel; do _scan_for_resources "$rel"; done < "$work/files.txt"

# ─── Cap on unresolved dependencies ─────────────────────────────────────────
unresolved_json="$(jq -sc '.' "$work/unresolved.jsonl")"
resources_json="$(jq -sc '.' "$work/resources.jsonl")"
capped="false"
if [[ "$(jq 'length' <<<"$unresolved_json")" -gt 0 ]]; then
  capped="true"
  resources_json="$(jq -c '[.[] | .namespace = "unknown"]' <<<"$resources_json")"
fi

resources_json="$(jq -c 'unique_by([.kind, .namespace, .detail, .location])' <<<"$resources_json")"
read_json="$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$work/files.txt")"

doc="$(jq -nc \
  --arg id "$run_unit_id" --argjson sources "$read_json" --argjson cap "$depth_cap" \
  --argjson res "$resources_json" --argjson unres "$unresolved_json" --argjson capped "$capped" \
  '{schema_version:"aid-test-resource-map-v1", run_unit_id:$id,
    source_paths:$sources, follow_depth_cap:$cap,
    resources:$res, unresolved_sources:$unres, capped_at_unknown:$capped}')"

if [[ -n "$out_path" ]]; then
  mkdir -p "$(dirname "$out_path")"
  printf '%s\n' "$doc" > "$out_path"
  printf '%s\n' "$out_path"
else
  printf '%s\n' "$doc"
fi
