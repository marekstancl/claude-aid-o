# C0 lens — reuse_evidence (P090)

Judges the QUALITY of each founding step's reuse search. Observe-only in E4; the file's
existence is what the `full`-band gate requires, its findings are advisory.
Does not re-derive what `aid-plan-lint.sh` already proved (that each declared result matches
its command — the plan lints clean).

stop_rule_blockers: []

findings:
  - step: 1
    verdict: adequate
    searched: "grep -n '^queue_[a-z_]*()' …/aid-queue-write.sh"
    assessment: |
      The search is by SHAPE of the thing (every exported queue function), not by the name the step
      is about to introduce — which is the failure mode this lens exists for. It found
      `queue_claim_next` and the step's decision is to SPLIT it rather than add a second selector.
      That is reuse, not founding.
  - step: 2
    verdict: adequate
    searched: "grep -n 'epic-merge-to-plan\\|cmd_epic' …/aid-plan-fsm.sh"
    assessment: |
      Aimed at the command layer the new subcommand joins. It could have been wider (the plan-FSM
      dispatcher is one file, so scope is not really a risk here), but the conclusion — "the
      command layer exists, add a subcommand" — is supported by what it found.
  - step: 3
    verdict: adequate, and the strongest of the seven
    searched: "grep -n claim-next …/skills/pipeline.md"
    assessment: |
      Searched the INSTRUCTION that describes the sequence rather than for a script named
      `aid-plan-continue`. It surfaced the exit-code table at `:2580` and the admission that no
      production caller exists — which is precisely the finding that justifies creating the file.
      A `Create:` step whose search looked for its own filename would have been the classic defect;
      this one avoided it.
  - step: 4
    verdict: adequate
    searched: "grep -rn '_resume_artifact_write\\|aid-auto-resume' …/scripts"
    assessment: |
      Repository-wide, by behaviour. It found the existing resume artifact WITH its producer and
      schema, and the step's decision not to extend it is argued from what the search found
      (a different subject, a different reader), not asserted.
  - step: 5
    verdict: adequate
    searched: "grep -rln 'aid_hook_rule' …/scripts/lib"
    assessment: |
      Found three existing handlers and adopts their shape. Scoped to one directory, but that is
      where hook handlers live by convention in this plugin.
  - step: 6
    verdict: adequate, though it was a late correction
    searched: "grep -rn 'aid-job.sh run' …/skills/pipeline.md"
    assessment: |
      This step exists ONLY because the PM pointed out that a supervisor already existed after the
      plan had declared the capability out of reach. The search now grounds it (`pipeline.md:151`,
      IMP-262). Worth recording: the earlier draft's failure was not a bad search — it was no
      search at all for that capability, because the plan had already concluded it did not exist.
  - step: 7
    verdict: adequate
    searched: "grep -c '^    not_guaranteed:' …/enforcement-registry.yaml"
    assessment: |
      A count, not a pattern hunt — appropriate for "does this field already exist and what is it
      called". It also caught the canonical spelling (`not_guaranteed`, 26 rows), which this
      session had to correct elsewhere.

observations:
  - The plan's reuse searches are unusually well-aimed at BEHAVIOUR rather than names. The one
    capability it missed (the job supervisor) was missed by reasoning, not by searching — the plan
    had concluded the capability was absent and therefore never searched for it. No lint and no
    lens catches that; a person did.

confidence: high
