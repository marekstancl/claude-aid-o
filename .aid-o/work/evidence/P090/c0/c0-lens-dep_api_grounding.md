# C0 lens — dep_api_grounding (P090)

Focus: does the plan build on an API that does not match the version actually in use?
Observe-only in E4.

stop_rule_blockers: []

findings:
  - id: DG-1
    severity: medium
    dependency: "claude CLI"
    finding: |
      Step 6 spawns `claude -p "/aid-run <epic_id>"`. Two grounded facts: this repository already
      invokes the CLI that way (`aid-hook-verify.sh:131`, with
      `--output-format stream-json --include-hook-events --verbose` under `timeout`), and that call
      site records a tool version via `tool_version claude`. What the plan does NOT establish is
      that a SLASH COMMAND passed to `-p` is a supported invocation — the canary passes plain
      prose ("Reply with the single word: ok"), not `/aid-run`.
    why_it_matters: |
      If `-p "/aid-run …"` is not dispatched as a command, the spawned session starts with a prompt
      it treats as text, and the EPIC never runs — while the job supervisor still reports a clean
      terminal result.
    recommendation: |
      Ground it before implementation: one manual `claude -p "/aid-help"` run, and record what came
      back. If slash dispatch is not supported under `-p`, the spawn prompt has to be prose that
      instructs the session to run the command.
  - id: DG-2
    severity: low
    dependency: "aid-job.sh (in-repo)"
    finding: |
      Step 6 uses `run --jobs-dir … --deadline … -- <cmd>` and later `collect`/`status` with a job
      id. Verified against the script's own header: those subcommands and flags exist, `collect` is
      idempotent, `status` needs an exact id, and `watchdog` is directory-scoped with no plan
      filter — which is why Step 4 stores the id. Grounded.
    assessment: no action.
  - id: DG-3
    severity: low
    dependency: "yq (mikefarah)"
    finding: |
      Step 6 reads configuration "the same way `aid-release-scope.sh:98-106` does". That call site
      carries a comment about mikefarah yq lacking jq's `empty`, requiring `.a[]?`. A new reader of
      config keys that are SCALARS (`spawn_next_epic`, `max_spawned_epics`) needs a different form
      than that list reader.
    recommendation: say the scalar form is used, so nobody copies the list idiom verbatim.

confidence: medium
