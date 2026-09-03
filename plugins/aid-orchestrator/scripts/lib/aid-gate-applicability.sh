#!/usr/bin/env bash
# aid-gate-applicability.sh — reads execution.yaml's `required_when`.
#
# WHY THIS FILE EXISTS (2026-09-02)
# --------------------------------
# `required_when` was written into all 14 gates of all 5 shipped stack
# templates, and into every project `/aid-init` ever created. The gate runner
# never read it. It read `required` alone, defaulting to false — so a failing
# pytest, ruff, mypy, eslint or tsc wrote `result: fail` into the report and
# left `overall: pass`. Two live consumers were in that state when this was
# found (acta, sousto-na-miru), and neither had done anything wrong: their
# configs were byte-identical to what AID had generated for them.
#
# The key separates two questions the runner had collapsed into one:
#   `required_when` — is this gate APPLICABLE to this tree at all?
#   the exit status — did the applicable check SUCCEED?
# A gate with nothing to check is not a passing gate; it is a gate that does
# not apply. Answering the first question honestly is what makes it safe to
# let the second one block.
#
# GRAMMAR — deliberately closed, and validated before anything runs
#   always
#   <glob> exists
#   <glob> OR <glob> [OR <glob>...] exists
# Nothing else. An unknown syntax is REFUSED, never quietly read as false:
# "I could not understand when this gate applies" and "this gate does not
# apply" are the two readings whose conflation caused the original defect.
#
# A NOTE ON THE SAME NAME ELSEWHERE. `aid-delivery-gate.sh` also reads a
# `required_when`, from the delivery-gate POLICY file, shaped as a list of
# condition objects (`always: true`, `has_lockfile: true`, …). Same word,
# different file, different schema, different reader. Reviewed and left as
# is: renaming either would cost a migration and resolve no runtime ambiguity.

_AID_GA_ERROR=""
_AID_GA_GLOBS=""
_AID_GA_ALWAYS=0
_AID_GA_REQUIRED=""
_AID_GA_SOURCE=""

# _aid_ga_parse <expr> — validate. Sets _AID_GA_ALWAYS=1 for `always`, or
# _AID_GA_GLOBS to one glob per line. Returns 0 valid / 1 malformed, with the
# reason in _AID_GA_ERROR.
#
# Results go into VARIABLES, not stdout: a command substitution runs this in a
# subshell, where an assignment to _AID_GA_ERROR is lost the moment it
# returns — the caller then reports a malformed expression with no reason.
# (The same trap is recorded in aid-source-plan-graph.sh.)
_aid_ga_parse() {
  local expr="$1"
  _AID_GA_ERROR=""; _AID_GA_GLOBS=""; _AID_GA_ALWAYS=0
  # Trim; a bare empty expression is malformed, not "always".
  expr="$(printf '%s' "$expr" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [[ -z "$expr" ]]; then
    _AID_GA_ERROR="empty required_when expression"
    return 1
  fi
  if [[ "$expr" == "always" ]]; then
    _AID_GA_ALWAYS=1
    return 0
  fi
  # Must end in the literal word `exists`.
  if [[ "$expr" != *" exists" ]]; then
    _AID_GA_ERROR="expected '<glob> exists' or 'always', got '${expr}'"
    return 1
  fi
  local body="${expr% exists}"
  body="$(printf '%s' "$body" | sed 's/[[:space:]]*$//')"
  [[ -n "$body" ]] || { _AID_GA_ERROR="no glob before 'exists' in '${expr}'"; return 1; }

  # Split on the literal separator ` OR `. Nothing else joins clauses: a lone
  # `or`, a comma or an `AND` is a refusal, not a guess at what was meant.
  local rest="$body" tok
  while :; do
    if [[ "$rest" == *" OR "* ]]; then
      tok="${rest%% OR *}"
      rest="${rest#* OR }"
    else
      tok="$rest"
      rest=""
    fi
    tok="$(printf '%s' "$tok" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -z "$tok" ]]; then
      _AID_GA_ERROR="empty clause in '${expr}'"
      return 1
    fi
    # A clause is a path glob. Whitespace inside one would make the ` OR `
    # split ambiguous, so it is refused rather than silently accepted.
    if [[ "$tok" == *[[:space:]]* ]]; then
      _AID_GA_ERROR="clause '${tok}' contains whitespace — clauses are joined by the literal ' OR ' and may not contain spaces"
      return 1
    fi
    _AID_GA_GLOBS+="${tok}"$'\n'
    [[ -n "$rest" ]] || break
  done
  return 0
}

# aid_gate_snapshot_candidates <root> — take THE snapshot, once per run, into
# the _AID_GA_CANDS array. Every applicability question is then answered from
# that one array, so two gates in the same run cannot disagree about what the
# tree contains.
#
# In a git repository: tracked files PLUS untracked-but-not-ignored ones. Both
# halves matter. Tracked-only would miss a brand-new `.py` that has not been
# committed yet — the exact moment a project most needs its Python checks to
# wake up. Including ignored files would wake them on `node_modules` and build
# output. Changed-files-only would be worse than both: an untouched failing
# suite still has to block.
#
# NUL-delimited, and read into an array rather than a newline-joined string: a
# filename may legally contain a newline, and splitting on newlines would turn
# one such file into two invented paths — which can flip a gate to
# "not applicable" and hand back a green run.
_AID_GA_CANDS=()
_AID_GA_SNAPSHOT_ROOT=""

aid_gate_snapshot_candidates() {
  local root="$1"
  _AID_GA_CANDS=()
  _AID_GA_SNAPSHOT_ROOT="$root"
  if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    # Submodules are deliberately NOT recursed into: `git ls-files` reports a
    # submodule as a single gitlink entry, so a superproject whose only Python
    # lives inside one does not activate `*.py exists`. A known limit, recorded
    # rather than papered over — the scope here is this repository's own files.
    #
    # A gate that must cover a submodule needs BOTH halves, and a command alone
    # is not enough: if required_when never activates, the command never gets
    # to matter. Either state `required: true` outright, or write a condition
    # that matches the gitlink itself (`vendor/foo exists`) — and make the
    # command recurse into the submodule.
    while IFS= read -r -d '' _c; do
      _AID_GA_CANDS+=("$_c")
    done < <(git -C "$root" -c core.quotepath=false ls-files -z --cached --others --exclude-standard 2>/dev/null)
    return 0
  fi
  while IFS= read -r -d '' _c; do
    _AID_GA_CANDS+=("${_c#"${root}/"}")
  done < <(find "$root" \
    \( -path "$root/.git" -o -path "$root/.aid-o/work" -o -path "$root/node_modules" \) -prune -o \
    -type f -print0 2>/dev/null)
}

# aid_gate_applicable <expr> <root>
#   0 = applicable, 1 = not applicable, 2 = malformed (reason in _AID_GA_ERROR)
#
# Matching: a clause WITHOUT a slash is matched against each candidate's
# BASENAME, so `*.py exists` is satisfied by `lib/nested/a.py` — which is what
# "the project has Python in it" means. A clause WITH a slash is matched
# against the whole root-relative path, and is additionally satisfied when any
# candidate lies beneath it, so `frontend/e2e exists` works for a directory.
aid_gate_applicable() {
  local expr="$1" root="$2"
  _AID_GA_ERROR=""
  # Called directly, never through $(...), so _AID_GA_ERROR survives. And the
  # `always` answer travels in its own flag rather than as a magic glob line:
  # `always exists` is a perfectly legal expression asking for a FILE named
  # `always`, and a shared channel made the two indistinguishable.
  _aid_ga_parse "$expr" || return 2
  (( _AID_GA_ALWAYS )) && return 0

  # One snapshot per root, reused. Re-taking it per gate would let two gates in
  # the same run answer from different trees.
  [[ "${_AID_GA_SNAPSHOT_ROOT}" == "$root" ]] || aid_gate_snapshot_candidates "$root"
  (( ${#_AID_GA_CANDS[@]} )) || return 1

  local g f base
  while IFS= read -r g; do
    [[ -n "$g" ]] || continue
    for f in "${_AID_GA_CANDS[@]}"; do
      [[ -n "$f" ]] || continue
      if [[ "$g" == */* ]]; then
        # shellcheck disable=SC2053
        [[ "$f" == $g || "$f" == "${g}"/* ]] && return 0
      else
        base="${f##*/}"
        # shellcheck disable=SC2053
        [[ "$base" == $g ]] && return 0
      fi
    done
  done <<< "$_AID_GA_GLOBS"
  return 1
}

# aid_gate_required <execution_yaml> <gate_name> <root>
#   Echoes "<true|false>\t<source>" where source is one of:
#     explicit          — the gate states `required:` and that wins outright
#     required_when     — derived from an applicable required_when
#     not_applicable    — required_when parsed, and nothing in the tree matches
#     legacy_default    — neither key present; the pre-2026-09 default of false
#   The same two values are ALSO left in _AID_GA_REQUIRED / _AID_GA_SOURCE, so
#   a caller can avoid `$(...)`: a command substitution runs this in a subshell
#   and _AID_GA_ERROR dies with it, leaving the caller to report "unreadable
#   requirement" with no reason — which is precisely the diagnosis a project
#   staring at a refused run needs.
#   Returns 0, or 2 with _AID_GA_ERROR set when required_when is malformed.
#
# The precedence is fixed and deliberate: an explicit `required:` always wins,
# including over a required_when that disagrees with it. That is the escape
# hatch a project needs to keep a gate advisory on purpose, and it is what a
# consumer is told to write when this change starts blocking something they
# had meant to leave advisory.
aid_gate_required() {
  local yaml="$1" gate="$2" root="$3"
  _AID_GA_ERROR=""; _AID_GA_REQUIRED=""; _AID_GA_SOURCE=""
  local explicit when explicit_set="" explicit_val=""

  # The explicit key is READ first but ACTED ON last. Returning here on sight
  # of `required:` would leave a malformed `required_when` on the same gate
  # unvalidated forever — and the worst version of that is a deliberately
  # advisory gate quietly carrying a broken expression nobody will ever be
  # told about. Both keys are checked; only then does precedence decide.
  #
  # `has("required")` and NOT `.required // ""`: yq's `//` is an alternative
  # over FALSY values, so `false // ""` yields "" — an explicit
  # `required: false` would vanish and be re-derived from required_when,
  # silently overriding the one line a project writes when it means a gate to
  # stay advisory. That is the same shape as the defect this file fixes.
  if [[ "$(yq -r ".gates.\"${gate}\" | has(\"required\")" "$yaml" 2>/dev/null)" == "true" ]]; then
    # The TAG, not the rendered text: `yq -r` prints `true` for the boolean
    # and for the string "true" alike, so a quoted value would be accepted by
    # a code path that documents booleans only.
    local rtag; rtag="$(yq -r ".gates.\"${gate}\".required | tag" "$yaml" 2>/dev/null)"
    explicit="$(yq -r ".gates.\"${gate}\".required" "$yaml" 2>/dev/null)"
    if [[ "$rtag" != "!!bool" ]]; then
      _AID_GA_ERROR="gate '${gate}': required must be an unquoted true or false, got ${rtag:-<unreadable>} ('${explicit}')"
      return 2
    fi
    case "$explicit" in
      true|false) explicit_set=1; explicit_val="$explicit" ;;
      *) _AID_GA_ERROR="gate '${gate}': required must be true or false, got '${explicit}'"; return 2 ;;
    esac
  fi

  local when_type
  when_type="$(yq -r ".gates.\"${gate}\" | has(\"required_when\")" "$yaml" 2>/dev/null)"
  if [[ "$when_type" != "true" ]]; then
    if [[ -n "$explicit_set" ]]; then
      _AID_GA_REQUIRED="$explicit_val"; _AID_GA_SOURCE=explicit
      printf '%s\texplicit\n' "$explicit_val"; return 0
    fi
    _AID_GA_REQUIRED=false; _AID_GA_SOURCE=legacy_default
    printf 'false\tlegacy_default\n'
    return 0
  fi
  when_type="$(yq -r ".gates.\"${gate}\".required_when | tag" "$yaml" 2>/dev/null)"
  if [[ "$when_type" != "!!str" ]]; then
    _AID_GA_ERROR="gate '${gate}': required_when must be a string ('always' or '<glob> exists'), got ${when_type:-<unreadable>}"
    return 2
  fi
  when="$(yq -r ".gates.\"${gate}\".required_when" "$yaml" 2>/dev/null)"

  # Validated even when it will not be consulted: a broken expression is a
  # broken config whether or not this particular gate happens to override it.
  if ! _aid_ga_parse "$when"; then
    _AID_GA_ERROR="gate '${gate}': ${_AID_GA_ERROR}"
    return 2
  fi
  if [[ -n "$explicit_set" ]]; then
    _AID_GA_REQUIRED="$explicit_val"; _AID_GA_SOURCE=explicit
    printf '%s\texplicit\n' "$explicit_val"; return 0
  fi

  local rc=0
  aid_gate_applicable "$when" "$root" || rc=$?
  case "$rc" in
    0) _AID_GA_REQUIRED=true;  _AID_GA_SOURCE=required_when;  printf 'true\trequired_when\n';   return 0 ;;
    1) _AID_GA_REQUIRED=false; _AID_GA_SOURCE=not_applicable; printf 'false\tnot_applicable\n'; return 0 ;;
    *) _AID_GA_ERROR="gate '${gate}': ${_AID_GA_ERROR}"; return 2 ;;
  esac
}
