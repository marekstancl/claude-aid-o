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
