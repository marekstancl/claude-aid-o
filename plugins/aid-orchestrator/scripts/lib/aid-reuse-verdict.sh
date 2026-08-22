#!/usr/bin/env bash
# =============================================================================
# aid-reuse-verdict.sh — the `**Reuse check:**` field: its grammar, its replay,
# and the verdict it produces when the search found conflicting patterns (P085).
#
# ONE file owns the whole notion of "did this step look for what already
# exists?", because two readers need it and they must not drift: the plan lint
# (presence + shape + replay, aid-plan-lint.sh) and the `reuse_evidence` C0 lens
# (quality of the answer, skills/review-checkpoint-contracts.md). The lint is
# the machine half, the lens the judgement half — and both grade the same four
# results, spelled here once.
#
# Sourced, not executed. Callers: aid-plan-lint.sh.
# =============================================================================

# THE result vocabulary. Four results, each with an English and a Czech
# spelling, longest-first so `several conflicting` is never read as `several
# matching`'s prefix or vice versa. Adding a spelling is one line here.
_AID_REUSE_RESULT_ALTS=(
  'several conflicting:several_conflicting'
  'several matching:several_matching'
  'více rozporných:several_conflicting'
  'vice rozpornych:several_conflicting'
  'více shodných:several_matching'
  'vice shodnych:several_matching'
  'one match:one'
  'jeden vzor:one'
  'none:none'
  'nic:none'
)

# THE read-only search vocabulary. Nothing outside it is ever run: the lint
# replays what the plan wrote, so the set of things it can be made to run is a
# security boundary, not a style preference.
_AID_REUSE_TOOLS=(grep rg ls find)

# …and the flags that would turn one of those four into a way to run something
# else. `find -exec`, `rg --pre`/`--search-zip` and `grep --devices` all end in
# an arbitrary program; `--config` lets ripgrep take its arguments from a file.
# The tool allowlist alone is not the boundary — these are the escapes out of
# it, so they are refused BY NAME rather than guessed at. Matched as a whole
# token or as the `--flag=value` form.
_AID_REUSE_REFUSED_FLAGS=(
  -exec -execdir -ok -okdir -delete -fprint -fprintf -fls
  --pre --pre-glob --search-zip -z --config --hostname-bin
  -D --devices --action --files-from
)

# aid_reuse_parse <field-value> — read one `**Reuse check:**` value.
# Echoes "<result-key>\t<command>" and returns 0, or "error:<reason>" and
# returns 1. Reasons (rendered by the caller, house style of
# _aid_classify_files_bullet):
#   no-command | command-not-allowed | command-unsafe | no-result
aid_reuse_parse() {
  local value="$1" rest tok cmd="" head="" key="" alt spell clean result named="" why
  local -a words
  # The command is the first backticked span that opens with an allowed tool.
  # Scanning for the tool rather than taking span #1 lets the sentence start
  # with a backticked path ("`lib/x.sh` exists, verified `grep …`") without
  # forcing an author into a word order.
  rest="$value"
  while [[ "$rest" == *'`'*'`'* ]]; do
    rest="${rest#*\`}"; tok="${rest%%\`*}"; rest="${rest#*\`}"
    read -r -a words <<<"$tok"
    head="${words[0]-}"
    # `git grep` is two words, and only its two-word form is a search: `git`
    # alone is not in the vocabulary.
    [[ "$head" == "git" ]] && head="git ${words[1]-}"
    for alt in "${_AID_REUSE_TOOLS[@]}" "git grep"; do
      [[ "$head" == "$alt" ]] && { cmd="$tok"; break 2; }
    done
    # Not a search — but it IS a command someone typed. Remembered so the
    # refusal can name it, which is a different message from "you wrote no
    # command at all".
    #
    # A SPACE is required: plans backtick single words constantly (config
    # values, field names, `general`/`vulcan`/`none`), and calling one of those
    # a refused command tells the author about a mistake they did not make.
    # A command someone actually ran has an argument.
    # …and the first word has to look like a command NAME: no dot, no slash.
    # `project.yaml → standards.active` is a backticked phrase with a space in
    # it, and it is not a program anybody ran.
    [[ -z "$named" && "$tok" == *" "* && "$head" =~ ^[a-z][a-z0-9_-]*$ ]] && named="$head"
  done
  if [[ -z "$cmd" ]]; then
    [[ -n "$named" ]] && { echo "error:command-not-allowed:${named}"; return 1; }
    echo "error:no-command"; return 1
  fi
  # A replayed command must be a SEARCH, not a program: no pipes, redirects,
  # chaining, substitution or newlines. Refused by name rather than sanitised —
  # a command this file cannot vouch for is not run at all.
  case "$cmd" in
    *[\|\;\&\>\<\$\(\)\{\}]*|*$'\n'*) echo "error:command-unsafe"; return 1 ;;
  esac
  # …and it must not carry a flag that hands execution to something else. With
  # the metacharacters already refused above, what `bash -c` still does for us
  # is word splitting, quote removal and globbing — nothing that starts a
  # second program. These flags are the remaining way to start one.
  for tok in $cmd; do
    # Quotes and backslashes come OFF first. `bash -c` removes them before the
    # tool ever sees the word, so a denylist that reads them would pass
    # `rg "--pre=./evil"` straight through — the hole this loop exists to close.
    clean="${tok//[\"\'\\]/}"
    for alt in "${_AID_REUSE_REFUSED_FLAGS[@]}"; do
      [[ "$clean" == "$alt" || "$clean" == "$alt="* ]] && { echo "error:command-flag-refused"; return 1; }
    done
  done
  # The result is read from AFTER the arrow, never from the whole sentence: a
  # search whose PATTERN is the word "none", or a reason that uses it in
  # passing, would otherwise declare a result nobody wrote.
  case "$value" in
    *"→"*)  result="${value#*→}" ;;
    *"->"*) result="${value#*->}" ;;
    *)      echo "error:no-result"; return 1 ;;
  esac
  for alt in "${_AID_REUSE_RESULT_ALTS[@]}"; do
    spell="${alt%%:*}"
    if [[ "$result" == *"$spell"* ]]; then key="${alt#*:}"; break; fi
  done
  [[ -n "$key" ]] || { echo "error:no-result"; return 1; }
  # A result that says something EXISTS owes the third part of the shape: why
  # what exists does not suffice. Without it a step can declare `one match` and
  # still found a new file in silence — which is the N+1 rule's whole subject,
  # only one result-key further along than `several conflicting`.
  #
  # NOT enforced for `none`: nothing was found, so there is nothing to explain.
  if [[ "$key" != "none" ]]; then
    why="${result#*"$spell"}"
    why="${why//[[:space:],:;—–-]/}"
    [[ "${#why}" -ge 15 ]] || { echo "error:no-reason"; return 1; }
  fi
  printf '%s\t%s' "$key" "$cmd"
}

# aid_reuse_replay <command> <cwd> — run one parsed search command and set
# AID_REUSE_HITS to how many FILES it found. Returns 0 on a clean run, 3 when
# the command itself failed (a broken or stale search is the author's finding,
# not the lint's), 4 on timeout, 5 when there is no `timeout` binary to bound
# it with.
#
# It SETS a variable rather than echoing one, and that is the whole reason the
# cache below works: a caller writing `$(aid_reuse_replay …)` runs it in a
# subshell, where every cache write and the `timeout` probe are discarded the
# moment it returns. A memoisation that the caller silently undoes is worse
# than none, because the comment claims a bound the code does not have.
#
# 20 s, because a search that takes longer than that is not evidence anyone can
# re-run; and bounded at all, because this is the one place a plan's own text
# becomes something the lint executes.
# bash 4+ is a prerequisite of this plugin (lib/common.sh check_prerequisites),
# so an associative array needs no fallback — and a `|| true` around `declare`
# would only hide a failure the subscripts below could not survive anyway.
declare -A _AID_REUSE_REPLAY_CACHE

AID_REUSE_HITS=0
aid_reuse_replay() {
  local cmd="$1" cwd="$2" out rc key
  AID_REUSE_HITS=0
  # Probed once per process, not once per founding step.
  if [[ -z "${_AID_REUSE_HAVE_TIMEOUT:-}" ]]; then
    command -v timeout >/dev/null 2>&1 && _AID_REUSE_HAVE_TIMEOUT=1 || _AID_REUSE_HAVE_TIMEOUT=0
  fi
  [[ "$_AID_REUSE_HAVE_TIMEOUT" -eq 1 ]] || return 5
  # Plans repeat one search across several founding steps; replaying it once is
  # the difference between a 20 s bound per PLAN and per STEP for that command.
  key="${cwd}"$'\x1f'"${cmd}"
  if [[ -n "${_AID_REUSE_REPLAY_CACHE[$key]+set}" ]]; then
    out="${_AID_REUSE_REPLAY_CACHE[$key]}"
    [[ "$out" == rc:* ]] && return "${out#rc:}"
    AID_REUSE_HITS="$out"; return 0
  fi
  out="$(cd "$cwd" 2>/dev/null && timeout 20 bash -c "$cmd" 2>/dev/null)"; rc=$?
  # 1 is "found nothing" for every tool in the vocabulary; 2+ is a real failure.
  [[ "$rc" -eq 124 ]] && { _AID_REUSE_REPLAY_CACHE[$key]="rc:4"; return 4; }
  [[ "$rc" -ge 2 ]] && { _AID_REUSE_REPLAY_CACHE[$key]="rc:3"; return 3; }
  # How many FILES the search found, not how many lines it printed: `grep -rn`
  # prints three lines for one file with three hits, and "one match" is a claim
  # about the file. Every tool in the vocabulary puts the path first and
  # colon-separates it (`grep -rn`, `grep -c`), or prints the path alone
  # (`ls`, `find`, `grep -l`), so the field before the first colon is the file
  # in all four cases.
  AID_REUSE_HITS="$(printf '%s' "$out" | awk 'NF { sub(/:.*/, ""); if (!seen[$0]++) c++ } END { print c + 0 }')"
  _AID_REUSE_REPLAY_CACHE[$key]="$AID_REUSE_HITS"
}

# aid_reuse_result_matches <result-key> <file-count> — does the replay agree
# with what the step declared? Three answers, because two would either miss the
# `one match`/`several` distinction or block on it:
#   0  agrees
#   1  CONTRADICTS — `none` over a search that finds something, or a claim of
#      existing patterns over a search that finds nothing. This is the shape the
#      plan named as blocking, and it does not depend on how output is counted.
#   2  the same direction, wrong degree — "one match" over four files, "several"
#      over one. Worth saying out loud, not worth blocking on: the file count is
#      read from tool output, and a tool can be asked to print in a shape this
#      reading gets wrong.
aid_reuse_result_matches() {
  case "$1" in
    none) [[ "$2" -eq 0 ]] && return 0; return 1 ;;
    one)  [[ "$2" -eq 0 ]] && return 1; [[ "$2" -eq 1 ]] && return 0; return 2 ;;
    *)    [[ "$2" -eq 0 ]] && return 1; [[ "$2" -eq 1 ]] && return 2; return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# The N+1 rule and its verdict (P085 Step 3)
# ---------------------------------------------------------------------------
# A plan never adds one more variant of something that already exists. It uses
# one of them, or it unifies them. What the MACHINE can decide is narrow and
# worth stating exactly: it sees the situation the step DECLARED. A step that
# says `several conflicting` and still founds another file of the same kind
# without an argument is refused here. A step that founds a duplicate without
# declaring anything is not visible to any regex — that is the `reuse_evidence`
# lens's work. So the rule this file enforces is not "N+1 cannot happen"; it is
# "N+1 cannot happen SILENTLY".
#
# The doclad for the threshold: nine unresolved backlog items about duplicates
# survive from the E-047 era (`isoNow()` in eight files, `TabButton` twice,
# `FilterChip`/`SegButton`, `safeStatus()`, `relativeCzech()`, `storage()`) —
# every one found by the Curator, none of them done. Filing an item unifies
# nothing, which is why "unify now" has to be reachable at all.

# THE spellings that count as declaring a second variant on purpose. A fixed
# phrase and not a heuristic: the check is "did the author make an argument",
# and only a phrase the author had to type answers that mechanically.
_AID_REUSE_DELIBERATE_ALTS=(
  'deliberately founding a variant'
  'vědomě zakládám variantu'
  'vedome zakladam variantu'
)

# aid_reuse_deliberate <field-value> — did the step argue for the second
# variant? Returns 0 when one of the spellings above appears.
aid_reuse_deliberate() {
  local alt tail
  for alt in "${_AID_REUSE_DELIBERATE_ALTS[@]}"; do
    [[ "$1" == *"$alt"* ]] || continue
    # AC10 asks for a SENTENCE, not for the phrase: a phrase on its own is a
    # password, and what makes it an argument is what follows it. Substance is
    # the test, deliberately, not the connective — "deliberately founding a
    # variant, because X" and "…: X is load-bearing and unifying is a separate
    # plan" are the same argument, and demanding the word `because` would grade
    # grammar rather than reasoning.
    tail="${1#*"$alt"}"
    tail="${tail//[[:space:],:;—-]/}"
    [[ "${#tail}" -ge 15 ]] && return 0
  done
  return 1
}

# aid_reuse_sites <field-value> <command> — the conflicting sites the field
# names: every backticked path in it except the ones inside the command itself
# (`grep -rn x src/known.ts` names a file, but as a search target, not a find).
aid_reuse_sites() {
  local value="$1" cmd="$2"
  # The COMMAND's text is cut out of the sentence, rather than each of its paths
  # being filtered from the result: a path can be both what the search looked at
  # and one of the conflicting sites it found, and dropping it by name would
  # silently shorten the very list the backlog item is supposed to carry.
  _aid_backtick_paths "${value//"$cmd"/ }"
}

# aid_reuse_verdict <field-value> <command> <declared-paths> — what to do about
# conflicting patterns. <declared-paths> is the plan's own path list, one per
# line. Echoes:
#   unify                  every conflicting site already lies inside what this
#                          plan touches, so unifying costs no new reach
#   backlog\t<p1,p2,…>     at least one site lies outside; the item names the
#                          sites, never "unify the components"
#   backlog                the field names no site at all, or the plan declares
#                          no paths — out of reach, and the fail-safe direction
#                          is the SMALLER intervention
#
# The second half of the threshold — that unifying does not push the step past
# its declared Effort — is deliberately NOT decided here. Nothing in the plan
# text measures it, and a verdict that pretended to would be the decoration
# this whole plan is against. The caller says it out loud to the author instead.
aid_reuse_verdict() {
  local value="$1" cmd="$2" declared="$3" site outside="" found=0 d inside
  while IFS= read -r site; do
    [[ -n "$site" ]] || continue
    found=1
    inside=0
    while IFS= read -r d; do
      [[ -n "$d" ]] || continue
      # Equal, or under a declared directory: `src/x/` covers `src/x/a.ts`.
      [[ "$site" == "$d" || "$site" == "${d%/}/"* ]] && { inside=1; break; }
    done <<< "$declared"
    [[ "$inside" -eq 1 ]] || outside="${outside:+$outside,}$site"
  done < <(aid_reuse_sites "$value" "$cmd")
  [[ "$found" -eq 1 ]] || { echo "backlog"; return 0; }
  [[ -n "$outside" ]] && { printf 'backlog\t%s' "$outside"; return 0; }
  echo "unify"
}
