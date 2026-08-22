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
  local value="$1" rest tok cmd="" first second key="" alt spell
  # The command is the first backticked span that opens with an allowed tool.
  # Scanning for the tool rather than taking span #1 lets the sentence start
  # with a backticked path ("`lib/x.sh` exists, verified `grep …`") without
  # forcing an author into a word order.
  rest="$value"
  while [[ "$rest" == *'`'*'`'* ]]; do
    rest="${rest#*\`}"; tok="${rest%%\`*}"; rest="${rest#*\`}"
    read -r first second <<<"$tok"
    [[ "$first" == "git" ]] && first="git $second"
    for alt in "${_AID_REUSE_TOOLS[@]}" "git grep"; do
      [[ "$first" == "$alt" ]] && { cmd="$tok"; break 2; }
    done
  done
  [[ -n "$cmd" ]] || { echo "error:no-command"; return 1; }
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
    for alt in "${_AID_REUSE_REFUSED_FLAGS[@]}"; do
      [[ "$tok" == "$alt" || "$tok" == "$alt="* ]] && { echo "error:command-flag-refused"; return 1; }
    done
  done
  for alt in "${_AID_REUSE_RESULT_ALTS[@]}"; do
    spell="${alt%%:*}"
    if [[ "$value" == *"$spell"* ]]; then key="${alt#*:}"; break; fi
  done
  [[ -n "$key" ]] || { echo "error:no-result"; return 1; }
  printf '%s\t%s' "$key" "$cmd"
}

# aid_reuse_replay <command> <cwd> — run one parsed search command and echo how
# many non-empty lines it produced. Returns 0 on a clean run, 3 when the command
# itself failed (a broken or stale search is the author's finding, not the
# lint's), 4 on timeout, 5 when there is no `timeout` binary to bound it with.
#
# 20 s, because a search that takes longer than that is not evidence anyone can
# re-run; and bounded at all, because this is the one place a plan's own text
# becomes something the lint executes.
aid_reuse_replay() {
  local cmd="$1" cwd="$2" out rc
  command -v timeout >/dev/null 2>&1 || return 5
  out="$(cd "$cwd" 2>/dev/null && timeout 20 bash -c "$cmd" 2>/dev/null)"; rc=$?
  # 1 is "found nothing" for every tool in the vocabulary; 2+ is a real failure.
  [[ "$rc" -eq 124 ]] && return 4
  [[ "$rc" -ge 2 ]] && return 3
  printf '%s' "$(printf '%s' "$out" | grep -c '[^[:space:]]' || true)"
}

# aid_reuse_result_matches <result-key> <hit-count> — does the replay agree with
# what the step declared? `none` must find nothing; every other result claims at
# least one existing pattern and must find one.
aid_reuse_result_matches() {
  if [[ "$1" == "none" ]]; then [[ "$2" -eq 0 ]]; else [[ "$2" -gt 0 ]]; fi
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
  local alt
  for alt in "${_AID_REUSE_DELIBERATE_ALTS[@]}"; do
    [[ "$1" == *"$alt"* ]] && return 0
  done
  return 1
}

# aid_reuse_sites <field-value> <command> — the conflicting sites the field
# names: every backticked path in it except the ones inside the command itself
# (`grep -rn x src/known.ts` names a file, but as a search target, not a find).
aid_reuse_sites() {
  local value="$1" cmd="$2" p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    [[ "$cmd" == *"$p"* ]] && continue
    printf '%s\n' "$p"
  done < <(_aid_backtick_paths "$value")
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
