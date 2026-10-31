#!/usr/bin/env bats
# aid-tier: t0
# aid-subject: plugins/aid-orchestrator/commands/aid-run.md
# The fixer's instruction names the evidence by an ABSOLUTE path in the state root. Defect it catches: a fixer working
# in the plan's worktree looked for merged.json relative to its own tree and did not find it (WAN P118 30. 10. 2026).

@test "both fixer prompts (CP2 round, CP7) say fix_of is an absolute path outside the worktree" {
  local f="$BATS_TEST_DIRNAME/../../../commands/aid-run.md"
  [ "$(grep -c "fix_of: <the ABSOLUTE " "$f")" -eq 2 ]
  grep -q "fix_of: <the ABSOLUTE " "$BATS_TEST_DIRNAME/../../../commands/aid-plan.md"
  [ "$(grep -c 'outside the .*worktree.*: read merged.json by this absolute path' "$f")" -eq 2 ]
}
