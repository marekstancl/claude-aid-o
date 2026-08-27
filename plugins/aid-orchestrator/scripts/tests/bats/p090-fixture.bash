#!/usr/bin/env bash
# p090-fixture.bash — the shapes the P090 continuation suites all need.
#
# WHY IT EXISTS. Five suites were each building the same three things by hand:
# a committed repo with a plan branch, the plan-state file `plan-start` writes,
# and a task branch that is (or is not) folded into the plan branch. The
# plan-state heredoc alone appeared verbatim four times — so the day a required
# field is added to that schema, as P090 itself just added `autonomy`, it is one
# edit here instead of four, and there is no fourth copy left to drift.
#
# It sits beside `generation-fixture.bash` and follows the same convention:
# `load p090-fixture.bash` after `test-helpers.bash`, and call the builders from
# `setup()`. Every function takes the root explicitly rather than reading a
# global, so a suite can build two workspaces if it ever needs to.

# p090_mk_workspace <root> — a committed repo with `.aid-o/` skeleton, the
# `.aid-o/`+`.aid-worktrees/` gitignore a real project has, and `plan/P090`.
#
# The gitignore matters more than it looks: without it, a fixture that runs
# `git add -A` after writing runtime state commits `.aid-o/work/` onto a task
# branch, and checking `main` back out then DELETES it. Three suites carried a
# hand-written warning about exactly that; the shared repo builder makes the
# warning unnecessary.
p090_mk_workspace() {
  local root="$1" plan="${2:-P090}"
  aid_test_mk_repo "$root" "$root/.aid-o/work/plan-state"
  git -C "$root" branch "plan/${plan}" main
}

# p090_plan_state <root> <plan_id> [autonomy] [plan_state] — the file
# `plan-start` writes. Defaults: autonomy=auto, plan_state=OPEN.
p090_plan_state() {
  local root="$1" plan="$2" autonomy="${3:-auto}" state="${4:-OPEN}"
  mkdir -p "${root}/.aid-o/work/plan-state/${plan}"
  cat > "${root}/.aid-o/work/plan-state/${plan}/plan-state.yaml" <<YML
plan_id: ${plan}
plan_state: ${state}
mode: plan_branch
plan_branch: plan/${plan}
target_branch: main
created_at: "2026-08-27T00:00:00Z"
current_operation: null
plan_final_attempt: 0
autonomy: ${autonomy}
YML
}

# p090_task_branch <root> <epic_id> [merged|unmerged] [plan_id]
#   A task branch with one commit. `merged` (the default) also fast-forwards the
#   plan branch onto it.
#
#   It branches off the PLAN branch, not off main: branching off main and then
#   moving the plan branch would silently drop whatever an earlier call had
#   already put there — a fixture bug that cost a debugging round.
p090_task_branch() {
  local root="$1" epic="$2" merged="${3:-merged}" plan="${4:-P090}"
  git -C "$root" branch "task/${epic}/main" "plan/${plan}"
  git -C "$root" checkout -q "task/${epic}/main"
  printf '%s\n' "$epic" > "${root}/work-${epic}.txt"
  git -C "$root" add "work-${epic}.txt"
  git -C "$root" commit -qm "${epic}: work"
  git -C "$root" checkout -q main
  [[ "$merged" == "merged" ]] && git -C "$root" branch -f "plan/${plan}" "task/${epic}/main"
  return 0
}

# p090_queue <file> <plan_id> <entry…> — a queue file from `<epic>:<status>[:<dep>]`
# triples, so a suite states the shape it needs on one line instead of a
# fifteen-line heredoc.
p090_queue() {
  local file="$1" plan="$2"; shift 2
  mkdir -p "$(dirname "$file")"
  {
    printf 'paused: false\n'
    printf 'last_modified: "2026-01-01T00:00:00Z"\n\n'
    printf 'queue:\n'
    local spec epic status dep
    for spec in "$@"; do
      epic="${spec%%:*}"; spec="${spec#*:}"
      status="${spec%%:*}"
      dep=""; [[ "$spec" == *:* ]] && dep="${spec#*:}"
      printf '  - epic_id: %s\n' "$epic"
      printf '    status: %s\n' "$status"
      printf '    plan_id: "%s"\n' "$plan"
      printf '    merge_target: "plan/%s"\n' "$plan"
      if [[ -n "$dep" ]]; then
        printf '    depends_on: ["%s"]\n\n' "$dep"
      else
        printf '    depends_on: []\n\n'
      fi
    done
  } > "$file"
}
