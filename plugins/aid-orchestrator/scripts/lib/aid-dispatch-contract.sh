#!/usr/bin/env bash
# =============================================================================
# lib/aid-dispatch-contract.sh — what an agent is handed, and what it must
# hand back (P087 Step 1)
#
#   aid_dispatch_contract_build    <plan.json> <step_index> <out_file> [evidence_root]
#   aid_dispatch_contract_prompt   <contract.json>
#   aid_dispatch_contract_extract  <output.md>
#   aid_dispatch_contract_validate <contract.json> <return.json> [tree_root]
#   aid_dispatch_contract_commit   <tree_root> <contract.json> <return.json> <message>
#
# WHY THIS EXISTS
#   Concurrent dispatch was written in 0.2.0 and switched off by a "TEMPORARY"
#   brake for three named reasons: mega-commits, placeholder verify files and
#   memory that agents were trusted to remember. All three come down to one
#   thing — the controller could not tell whether an agent received what it
#   was meant to and returned what it was meant to. This file is that telling.
#
# THE PACKET
#   Built from plan.json by code, not assembled in a prompt: the step's
#   objective, its allowed paths, what it depends on, the artifacts it is
#   expected to leave behind, its acceptance criteria, the UI contract when
#   there is one, its own evidence directory — and a VERSION, a hash of all of
#   that. The agent must quote the version back. A return against a stale
#   packet is refused, never merged.
#
# THE RETURN
#   One JSON object in the agent's output, in a fenced block tagged
#   `aid-return`. It names the version it worked against, the files it changed,
#   the gates it ran and the step's status. Validation checks the return
#   against the PACKET and the DISK — an expected artifact has to exist, not be
#   declared; every file git sees changed in the tree has to be in the list,
#   so an edit the agent left out is a rejection, not a secret — and it names
#   every file changed outside the allowed paths, which is what makes a scope
#   violation visible instead of a surprise at merge time.
#
# WHAT IT DOES NOT DO
#   It does not run the agent and it does not decide the FSM. A step with no
#   declared paths owes no contract (exit 3), so a pure-analysis step is not
#   made to fake one.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-25
# =============================================================================
[[ -n "${_AID_DISPATCH_CONTRACT_SH_LOADED:-}" ]] && return 0
_AID_DISPATCH_CONTRACT_SH_LOADED=1

_AID_DCT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-scoping.sh
source "${_AID_DCT_LIB_DIR}/aid-scoping.sh"

# The tag on the fenced block the agent returns. One spelling, used by the
# prompt that asks for it and the reader that finds it.
_AID_DCT_RETURN_FENCE='aid-return'

# _aid_dc_version <contract_body_json> — twelve hex digits of the canonical
# body. Long enough that a stale packet never collides, short enough to quote.
_aid_dc_version() {
  printf '%s' "$(jq -S -c . <<< "$1")" | sha256sum | cut -c1-12
}

# ---------------------------------------------------------------------------
# aid_dispatch_contract_build <plan.json> <step_index> <out_file> [evidence_root]
#   0  written
#   1  plan unreadable or the step does not exist
#   3  the step declares no paths — no contract is owed (a plan decision: a
#      pure-analysis step is not made to fake artifacts; its output.md is
#      still verified by the step-verify file like any other)
#
# <evidence_root> is the run's evidence directory; with it the packet carries
# the step's ABSOLUTE evidence path, which is what an agent in a per-step
# worktree needs — a relative one would point into its own tree.
#
# Expected artifacts are the Create/Test/Rewrite bullets of `outputs`: paths
# the step promises to leave behind. A Modify bullet promises nothing new, so
# it is not an artifact; it stays an allowed path.
# ---------------------------------------------------------------------------
aid_dispatch_contract_build() {
  local plan="${1:?contract: plan.json required}" idx="${2:?contract: step index required}" out="${3:?contract: output file required}" evroot="${4:-}"
  [[ -r "$plan" ]] || { echo "contract: cannot read ${plan}" >&2; return 1; }
  [[ "$idx" =~ ^[0-9]+$ ]] || { echo "contract: step index must be a number, got '${idx}'" >&2; return 1; }

  local step
  step="$(jq -c --argjson i "$idx" '.steps[$i] // empty' "$plan" 2>/dev/null)"
  [[ -n "$step" ]] || { echo "contract: ${plan} has no step at index ${idx}" >&2; return 1; }

  if [[ "$(jq -r '(.allowed_paths // []) | length' <<< "$step")" == "0" ]]; then
    echo "contract: step ${idx} declares no paths — no contract is owed" >&2
    return 3
  fi

  # Artifacts: the paths behind Create/Test/Rewrite bullets, in declaration
  # order, each once. Read with the same splitter the scoping lint uses, so a
  # bullet the lint accepts is a bullet this reads.
  local -a artifact_paths=()
  local bullet body p
  while IFS= read -r bullet; do
    [[ "$bullet" =~ ^(Create|Test|Rewrite):[[:space:]]* ]] || continue
    body="${bullet#*:}"; body="${body#"${body%%[![:space:]]*}"}"
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      artifact_paths+=("$p")
    done < <(_aid_split_path_entry "$body" 2>/dev/null || true)
  done < <(jq -r '.outputs[]? // empty' <<< "$step")
  local artifacts='[]'
  if (( ${#artifact_paths[@]} > 0 )); then
    artifacts="$(printf '%s\n' "${artifact_paths[@]}" | awk '!seen[$0]++' | jq -Rsc 'split("\n") | map(select(length > 0))')"
  fi

  local step_id; step_id="$(jq -r '.id // ""' <<< "$step")"

  local body_json
  body_json="$(jq -c \
    --argjson i "$idx" \
    --argjson artifacts "$artifacts" \
    --arg evidence "${evroot:+${evroot%/}/}steps/${step_id}" \
    --slurpfile plan "$plan" \
    --arg id "$step_id" \
    '{
      step_index: $i,
      step_id: .id,
      role: .role,
      objective: .objective,
      allowed_paths: (.allowed_paths // []),
      forbidden_paths: (.forbidden_paths // []),
      depends_on: [ ($plan[0].dependencies // [])[] | select(.after == $id) | .before ],
      expected_artifacts: $artifacts,
      acceptance_criteria: (.acceptance_criteria // []),
      ui_change_contract: (.ui_change_contract // null),
      evidence_dir: $evidence
    }' <<< "$step")" || { echo "contract: could not assemble the packet for step ${idx}" >&2; return 1; }

  local version; version="$(_aid_dc_version "$body_json")"
  jq --arg v "$version" '. + {version: $v,
      return_shape: {contract_version: "<the version above, quoted back>",
                     changed_files: ["<every file you changed, repo-relative>"],
                     gates: [{name: "<gate>", result: "pass|fail|skipped"}],
                     step_status: "done|blocked"}}' <<< "$body_json" > "$out" \
    || { echo "contract: could not write ${out}" >&2; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# aid_dispatch_contract_prompt <contract.json>
#   Prints the packet as the block the controller pastes into the dispatch
#   prompt — the packet verbatim (the agent gets content, never a path) and
#   the return it owes, in the shape the reader below understands.
# ---------------------------------------------------------------------------
aid_dispatch_contract_prompt() {
  local c="${1:?contract: contract file required}"
  [[ -r "$c" ]] || { echo "contract: cannot read ${c}" >&2; return 1; }
  local version; version="$(jq -r '.version' "$c")"
  cat <<PROMPT
## Dispatch Contract (version ${version})

\`\`\`json
$(jq 'del(.return_shape)' "$c")
\`\`\`

Write evidence only under \`$(jq -r '.evidence_dir' "$c")\`. Change files only
under the allowed paths. When you finish, end your output with a fenced block
tagged \`${_AID_DCT_RETURN_FENCE}\` holding this object (the LAST such block is
the one read):

\`\`\`${_AID_DCT_RETURN_FENCE}
$(jq '.return_shape | .contract_version = "'"$version"'"' "$c")
\`\`\`

A return without this block, or against another version, is refused and the
step is dispatched again.
PROMPT
}

# ---------------------------------------------------------------------------
# aid_dispatch_contract_extract <output.md>
#   Prints the return object from the LAST `aid-return` fenced block. Exit 1
#   when there is none or it is not one JSON object — a return that cannot be
#   read is not a return.
# ---------------------------------------------------------------------------
aid_dispatch_contract_extract() {
  local out="${1:?contract: output file required}"
  [[ -r "$out" ]] || { echo "contract: cannot read ${out}" >&2; return 1; }
  local block
  block="$(awk -v tag="$_AID_DCT_RETURN_FENCE" '
    $0 ~ "^```" tag "[[:space:]]*$" { inside=1; buf=""; next }
    inside && /^```[[:space:]]*$/   { inside=0; last=buf; next }
    inside                          { buf = buf $0 "\n" }
    END { printf "%s", last }' "$out")"
  [[ -n "$block" ]] || { echo "contract: ${out} carries no \`${_AID_DCT_RETURN_FENCE}\` block" >&2; return 1; }
  jq -c 'if type == "object" then . else error("not an object") end' <<< "$block" 2>/dev/null \
    || { echo "contract: the ${_AID_DCT_RETURN_FENCE} block in ${out} is not one JSON object" >&2; return 1; }
}

# _aid_dc_path_allowed <path> <allowed-json> <own_evidence_suffix> — bash glob
# match, the same way scripts/gates/scope-check.sh decides. A step's own
# evidence directory is always allowed: that is where its output is meant to go.
_aid_dc_path_allowed() {
  local path="$1" allowed="$2" evidence="$3" pattern
  # The evidence dir matches as a whole path segment, never as a substring:
  # `steps/step_1` must not cover `steps/step_1_extra`.
  case "$path" in "$evidence"|"$evidence"/*|*/"$evidence"|*/"$evidence"/*) return 0 ;; esac
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] || continue
    # shellcheck disable=SC2254
    case "$path" in $pattern) return 0 ;; esac
    # A declared directory covers what is under it.
    [[ "$path" == "${pattern%/}/"* ]] && return 0
  done < <(jq -r '.[]' <<< "$allowed")
  return 1
}

# ---------------------------------------------------------------------------
# aid_dispatch_contract_validate <contract.json> <return.json> [tree_root]
#   Prints ONE JSON report:
#     {verdict: "accept"|"reject", reasons: [...],
#      missing_artifacts: [...], out_of_scope: [...], foreign_evidence: [...],
#      undeclared_changes: [...], extra_artifacts: [...]}
#   0 accept · 1 reject · 2 cannot judge (unreadable input)
#
#   Everything is checked against <tree_root> (default: cwd). Artifacts must
#   exist on disk; when the root is a git tree, every path git reports as
#   changed (tracked or untracked, `.aid-o/` excluded) must appear in the
#   return's `changed_files` — the list is the agent's DECLARATION, the disk is
#   the fact, and a change left out of the declaration is refused. Scope is
#   judged over the union of the two. `extra_artifacts` — declared, in scope,
#   not promised — is recorded, never refused.
# ---------------------------------------------------------------------------
# aid_dispatch_contract_allowed <contract.json> — the step's allowed paths AS
#   OF NOW: the packet's list, plus any `aid-fsm.sh amend-scope` record beside
#   it. The record sits in the step's evidence dir, which the agent can write,
#   so it is NOT trusted on its own: an amended path counts only if plan.json
#   (which amend-scope widened and the increment-step hash protects) lists it
#   for this step too. The record says why; plan.json says whether. Every
#   reader of a step's scope (the return validator, the write-hook notice)
#   goes through here so none of them can disagree.
aid_dispatch_contract_allowed() {
  local c="$1" allowed
  allowed="$(jq -c '.allowed_paths // []' "$c")"
  local amend_file; amend_file="$(dirname "$c")/scope-amendment.json"
  [[ -f "$amend_file" ]] || { printf '%s' "$allowed"; return 0; }
  local plan_json="" cand sid
  for cand in "$(dirname "$c")/../../plan.json" "$(dirname "$c")/plan.json"; do
    [[ -f "$cand" ]] && { plan_json="$cand"; break; }
  done
  [[ -n "$plan_json" ]] || { printf '%s' "$allowed"; return 0; }
  sid="$(jq -r '.step_id // ""' "$c")"
  jq -c --slurpfile a "$amend_file" --slurpfile p "$plan_json" --arg sid "$sid" '
    (($p[0].steps // []) | map(select(.id == $sid)) | .[0].allowed_paths // []) as $planned
    | . + ([$a[0][]? | .paths[]?] | map(select(. as $x | $planned | index($x)))) | unique' <<<"$allowed" 2>/dev/null \
    || printf '%s' "$allowed"
}

aid_dispatch_contract_validate() {
  local c="${1:?contract: contract file required}" r="${2:?contract: return file required}" root="${3:-.}"
  [[ -r "$c" ]] || { echo "contract: cannot read ${c}" >&2; return 2; }
  [[ -r "$r" ]] || { echo "contract: cannot read ${r}" >&2; return 2; }
  jq -e 'type == "object"' "$c" >/dev/null 2>&1 || { echo "contract: ${c} is not a JSON object" >&2; return 2; }

  local reasons="[]" missing="[]" out_of_scope="[]" foreign="[]" extra="[]"
  _add() { local -n arr="$1"; arr="$(jq -c --arg x "$2" '. + [$x]' <<< "$arr")"; }

  if ! jq -e 'type == "object"' "$r" >/dev/null 2>&1; then
    _add reasons "the return is not a JSON object"
    jq -n --argjson reasons "$reasons" '{verdict: "reject", reasons: $reasons, missing_artifacts: [], out_of_scope: [], foreign_evidence: [], extra_artifacts: []}'
    return 1
  fi

  local want got
  want="$(jq -r '.version' "$c")"
  got="$(jq -r '.contract_version // ""' "$r")"
  if [[ -z "$got" ]]; then
    _add reasons "the return does not confirm a contract version (expected ${want})"
  elif [[ "$got" != "$want" ]]; then
    _add reasons "the return confirms contract version ${got}, the dispatched packet is ${want} — the agent worked against stale instructions"
  fi

  jq -e '.changed_files | type == "array" and all(.[]; type == "string")' "$r" >/dev/null 2>&1 || _add reasons "the return lists no changed_files array of paths"
  jq -e '.gates | type == "array" and all(.[]; type == "object" and (.name | type == "string") and (.result | IN("pass","fail","skipped")))' "$r" >/dev/null 2>&1 \
    || _add reasons "the return's gates are not a list of {name, result: pass|fail|skipped}"
  jq -e '.step_status | IN("done","blocked")' "$r" >/dev/null 2>&1 || _add reasons "the return's step_status is not done|blocked"

  # Artifacts: on the disk, not in the declaration.
  local expected declared a
  expected="$(jq -r '.expected_artifacts[]? // empty' "$c")"
  declared="$(jq -r '.changed_files[]? // empty' "$r")"
  while IFS= read -r a; do
    [[ -n "$a" ]] || continue
    # An ABSOLUTE expected artifact is checked where it actually is, not glued
    # behind the tree root. A step whose output lives in another repository
    # (a plan may declare one deliberately) otherwise produced
    # `<root>//opt/eco/docs/...`, which never exists — so the contract refused a
    # step whose files were both on disk and already reviewed (WAN P099 step 11,
    # reported 2026-08-27; the plan there declares one absolute and one relative
    # artifact, and NO single root satisfies both).
    local _a_path; [[ "$a" == /* ]] && _a_path="$a" || _a_path="${root}/${a}"
    [[ -e "$_a_path" ]] || _add missing "$a"
  done <<< "$expected"
  [[ "$missing" != "[]" ]] && _add reasons "expected artifacts are missing on disk: $(jq -r 'join(", ")' <<< "$missing")"

  # The disk's own list of changes, when there is a git tree to ask. A file
  # changed but not declared is refused: the declaration is what the commit
  # stages, so an omission would leave an edit behind unstaged and unseen.
  local undeclared="[]" changed_on_disk="" g
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # `core.quotepath=false` — WITHOUT it git escapes any non-ASCII byte, so a
    # file named `příloha.md` comes back as "p\305\231\303\255loha.md", never
    # matches the declared path, and the step is refused although everything
    # about it is correct (WAN, reproduced 2026-09-02). The quoting is git's
    # display convention, not the file's name.
    #
    # A name containing a NEWLINE would still break this line-oriented read;
    # `--porcelain -z` is the durable answer and is not taken here because it
    # changes how every consumer below reads the value. Recorded rather than
    # implied: a plan touching such a file is the input that finds it.
    changed_on_disk="$(git -C "$root" -c core.quotepath=false status --porcelain --untracked-files=all 2>/dev/null \
      | cut -c4- | sed 's/^.* -> //' | grep -v '^\.aid-o/' || true)"
    while IFS= read -r g; do
      [[ -n "$g" ]] || continue
      grep -qxF -- "$g" <<< "$declared" || _add undeclared "$g"
    done <<< "$changed_on_disk"
    [[ "$undeclared" != "[]" ]] && _add reasons "files changed on disk but not declared in the return (the agent left them out, or the tree was already dirty before dispatch — a step is dispatched from a clean tree): $(jq -r 'join(", ")' <<< "$undeclared")"
  fi

  # Scope, over the declared list AND the disk's: every file outside the
  # allowed paths is named.
  local allowed evidence f
  allowed="$(aid_dispatch_contract_allowed "$c")"
  evidence="steps/$(jq -r '.step_id // ""' "$c")"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ "$f" == *"/steps/step_"* ]] && ! _aid_dc_path_allowed "$f" '[]' "$evidence"; then
      _add foreign "$f"
    elif ! _aid_dc_path_allowed "$f" "$allowed" "$evidence"; then
      _add out_of_scope "$f"
    elif [[ "$f" != *"${evidence}"* ]] && ! grep -qxF -- "$f" <<< "$expected"; then
      _add extra "$f"
    fi
  done < <(printf '%s\n%s\n' "$declared" "$changed_on_disk" | awk 'NF && !seen[$0]++')
  [[ "$foreign" != "[]" ]] && _add reasons "evidence written into another step's directory: $(jq -r 'join(", ")' <<< "$foreign")"
  [[ "$out_of_scope" != "[]" ]] && _add reasons "files changed outside the allowed paths: $(jq -r 'join(", ")' <<< "$out_of_scope")"

  local verdict="accept"
  [[ "$reasons" != "[]" ]] && verdict="reject"
  jq -n --arg v "$verdict" --argjson reasons "$reasons" --argjson missing "$missing" \
        --argjson oos "$out_of_scope" --argjson foreign "$foreign" --argjson undeclared "$undeclared" --argjson extra "$extra" \
        '{verdict: $v, reasons: $reasons, missing_artifacts: $missing, out_of_scope: $oos,
          foreign_evidence: $foreign, undeclared_changes: $undeclared, extra_artifacts: $extra}'
  [[ "$verdict" == "accept" ]]
}

# ---------------------------------------------------------------------------
# aid_dispatch_contract_commit <tree_root> <contract.json> <return.json> <message>
#   The controller's per-step commit: VALIDATES the return against the
#   contract first (a rejected return is not committed — exit 1 with the
#   report), then stages ONLY the files the return names, commits them in
#   <tree_root> and prints the commit SHA. An agent that changed nothing
#   produces no commit — "nothing to commit" on stdout, exit 0 — never an
#   empty one. Exit 1 when git refuses.
#
#   One step, one commit, made by the controller after validation: that is
#   what makes a mega-commit impossible even when three agents return at once,
#   because the controller takes them one at a time.
# ---------------------------------------------------------------------------
aid_dispatch_contract_commit() {
  local root="${1:?contract: tree root required}" c="${2:?contract: contract file required}" r="${3:?contract: return file required}" msg="${4:?contract: commit message required}"
  local report
  if ! report="$(aid_dispatch_contract_validate "$c" "$r" "$root")"; then
    echo "contract: the return is not accepted, nothing is committed — $(jq -r '.reasons | join("; ")' <<< "$report" 2>/dev/null)" >&2
    return 1
  fi
  local -a files=()
  local f
  # Present on disk, or tracked and deleted — a declared deletion is a
  # change like any other and is staged as one.
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ -e "${root}/${f}" ]] || git -C "$root" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then files+=("$f"); fi
  done < <(jq -r '.changed_files[]? // empty' "$r")
  if [[ "${#files[@]}" -eq 0 ]]; then
    echo "nothing to commit"
    return 0
  fi
  git -C "$root" add -A -- "${files[@]}" 2>/dev/null || { echo "contract: git add refused in ${root}" >&2; return 1; }
  if git -C "$root" diff --cached --quiet; then
    echo "nothing to commit"
    return 0
  fi
  git -C "$root" commit -q -m "$msg" 2>/dev/null || { echo "contract: git commit refused in ${root}" >&2; return 1; }
  git -C "$root" rev-parse HEAD
}
