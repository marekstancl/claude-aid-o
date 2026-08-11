# C0 lens: planned_call_feasibility — P080 (observe, advisory)

_generated_by: aid-orchestrator:verifier@c0-lens-planned_call_feasibility
_generated_at: 2026-08-11T04:29:24Z
Reviewed-Head: 6154ebd714cc69ffa4dd222542cf1e820e078ab8

stop_rule_blockers:
  - id: C0-PCF-1
    step: 12
    claim: "Step 12's renderer takes `pm-decision-brief.json` as its ONLY input and extracts `reviewed candidate SHA, approved target, merge SHA, tag status, EPIC count, gate totals`; its fail-closed rule makes a brief 'missing a labelled fact' exit 1."
    evidence: "`pm-decision-brief.json` does not carry any of those fields. The payload builder `scripts/aid-pm-brief.sh:build_brief_payload()` (lines 109-133) emits a CLOSED key set: communication_status, release_ready, blockers, waivers_applied, human_summary_path, merge_mode, evidence_verification_status, evidence_verified_at_head, reporter_status, reporter_reason, simplifier_status, simplifier_reason, summary_for_pm, delivered_summary_ref. `plan_summary` is read at aid-pm-brief.sh:232 ONLY inside `build_brief_md()` (the markdown renderer) and comes from `release-decision.json` (`.release_decision.plan_summary`, schema at defaults/schemas/release-decision.schema.json:172-181), never from the brief. Verified on two real artifacts: `jq '.pm_decision_brief|keys'` on .aid-o/work/evidence/E-061-3_6/R-E061-3/pm-decision-brief.json and .aid-o/work/evidence/E-059-2_2/R-E059-2/reporter/smoke/pm-decision-brief.json returns the 14-key set above; `.pm_decision_brief|has(\"plan_summary\")` = false on both. The four labelled facts are enforced only against pm-summary.md (aid-plan-fsm.sh:6653 loops over the literals \"Reviewed candidate SHA:\", \"Approved target SHA:\", \"Final main merge SHA:\", \"Release / tag status:\"). No step in P080 adds these fields to the brief — Step 12 explicitly declares `aid-pm-brief.sh` UNTOUCHED. Consequence as written: the Step 12 renderer exits 1 on every real brief, and its own bats fixtures would have to be synthetic briefs that no producer can generate."

findings:
  - id: C0-PCF-F1
    severity: high
    step: 12
    finding: "The Decision-required card's A/B/C alternatives are declared to be 'populated from the brief's options', and the card is selected 'when the brief says the merge decision is pending' — the brief has neither an options set nor a pending-decision reason field."
    evidence: "`grep -n 'options' scripts/aid-pm-brief.sh` returns nothing. The nearest fields are `merge_mode` (enum manual|auto|blocked, validated at aid-release-policy.sh: `case merge_mode in manual|auto|blocked`) and `release_ready` (boolean) — neither encodes 'pending', and no field carries a decision reason or an option list. Related vocabulary mismatch in the same step: the plan's tag-status tile expects `tagged|untagged|pending`, but the producer emits `release_tag_status` defaulting to `not_tagged` (aid-pm-brief.sh:260, aid-release-policy.sh:1128)."
    recommendation: "Either (a) extend `build_brief_payload()` to echo `plan_summary` plus an explicit `decision: {state, reason, options[]}` block (this reopens the 'aid-pm-brief.sh untouched' constraint and needs its own step + schema/bats update), or (b) redefine Step 12's input as `release-decision.json` (which does carry plan_summary) while keeping the no-sibling-evidence cycle-break, or (c) let the renderer read pm-summary.md's labelled lines. Pick one at plan level and restate Step 12's facts list against the real key set, including the actual tag-status vocabulary."

  - id: C0-PCF-F2
    severity: high
    step: 11
    finding: "The Blocked card's `Doporučené řešení` line is specified as 'the failed gate's registered fix-loop command line'. No gate carries a registered fix command anywhere in the repo, so a deterministic renderer has nothing to read."
    evidence: "Gate rows in `defaults/execution.yaml` have exactly the keys description, required, command, timeout_seconds, pass_criteria (`yq '.gates|to_entries|.[0].value|keys'`). `grep -n 'fix' defaults/execution.yaml` finds only a commented example command and `auto_fix_patterns` (line 311), which is a review/fix-loop pattern list, not a per-gate remediation command. Gate report rows likewise carry no fix field (real report keys: attempts, duration_ms, exit_code, gate, output, result — verified on .aid-o/work/evidence/E-061-1_6/R-E061-1/gates/gates_report.json)."
    recommendation: "Either add a `fix_command:` (or `remediation:`) key to the gate schema in an earlier step and populate it for the shipped gates, or downgrade the line to a deterministic template that cites the failed gate's own `command` + the public force command (both of which DO exist) and say so in Step 11's Implementation Detail."

  - id: C0-PCF-F3
    severity: high
    step: 9
    finding: "Step 9 codifies the language rule as 'documents per `document_language` from `.aid-o/config/language.yaml`' into the new SSOT contract file. That config file does not exist and is not shipped; the key lives in orchestration.yaml. Steps 11/12/14/15 then consume this contract, and the deterministic renderers additionally have no declared input for the PM's conversation language at all."
    evidence: "`ls .aid-o/config/` shows no language.yaml (execution/integrations/permissions/plugin/project/queue/... only). `ls defaults/*.yaml` ships no language.yaml. The authority is `defaults/orchestration.yaml:10 → language.document_language: EN` (orchestration.yaml:2 header states it was consolidated FROM language.yaml). The stale path is already copied in skills/brainstorming.md:399,406,504, skills/plan-writing.md:1148, agents/reporter.md:85 — Step 9 would promote that stale cite into the file every other step points at. Separately: Steps 11/12 hardcode Czech card labels (`Doporučené řešení`, `Proč teď`, `Riziko`, `Doporučení:` — Step 12 AC asserts the literal `Doporučení:`) inside bash renderers, while Step 9 says 'cards render in the PM's language; these examples are Czech because the requirements were' and Step 15 says 'a structural grep asserts card labels, not Czech literals, so other locales pass'. No step gives the renderers a language input, so the emitted labels are unconditionally Czech and the Step 9/15 language contract is unsatisfiable as stated."
    recommendation: "In Step 9, cite the real source (`orchestration.yaml → language.document_language`, with the `.aid-o/config/orchestration.yaml` override path) and state explicitly that deterministic renderer LABELS are a fixed locale (name it) while model-written prose blocks follow the PM's language — or add a locale argument to the renderer signatures in Step 10 and thread it through Steps 11/12."

  - id: C0-PCF-F4
    severity: medium
    step: 11
    finding: "Step 11 names `lib/aid-run-gates-report.sh` as the producer of its input ('verified canonical input per grounding'). That lib does not produce the gate report — it only merges an escalation pair, and only when a targeted→full escalation fires."
    evidence: "`scripts/lib/aid-run-gates-report.sh` is 41 lines and exports exactly one function, `merge_escalation_report <targeted_report_json> <full_report_json> <reason>` (header lines 1-31). The actual report is assembled and written by `scripts/aid-run-gates.sh` (report_path default `${_evidence_dir}/gates/gates_report.json`, aid-run-gates.sh:1629; final envelope jq at :2536). The needed fields DO exist there (gate/result/exit_code/duration_ms/attempts per row, top-level overall, plus `waived_gates[]` added at :2512-2537 per IMP-270), so the input is feasible — only the named producer is wrong."
    recommendation: "Restate Step 11's input as `gates_report.json` produced by `aid-run-gates.sh` (path `<evidence>/gates/gates_report.json`), noting that `merge_escalation_report` output is the same shape plus an additive `escalation` key so both are consumable. Also note the `gates` value is an OBJECT keyed by gate name, not an array of rows — the plan's phrase 'jq over the merged report rows' needs `to_entries`."

  - id: C0-PCF-F5
    severity: medium
    step: 11
    finding: "Step 11's waiver facts are 'waiver ids + scopes + expiry'. Waiver documents have no `id` and no `scope` field."
    evidence: "`aid-gate-waiver.sh:cmd_issue()` (lines 163-180) writes exactly: schema_version, artifact_type, gate_id, project_id, epic_id, run_id, head_sha, command_sha256, authorized_by, reason, issued_at, expires_at, single_use, payload_sha256, consumed{at,by_run}. Path is `<evidence>/waivers/gate-waiver-<gate>.json` (aid-run-gates.sh:2151). The verdict vocabulary the plan cites is real and slightly wider than stated: valid|missing|expired|consumed|head_mismatch|command_mismatch|forged (aid-gate-waiver.sh:22), plus `already_consumed` from consume and the `waiver_rejected:<verdict>` / `waiver_ref` row stamps (aid-run-gates.sh:2167-2179)."
    recommendation: "Rewrite the facts list to the real fields (gate_id as the scope, expires_at, authorized_by, reason, consumed.at) and use the full 7-value verdict enum in the fixture assertions so an `expired`/`forged`/`head_mismatch` waiver cannot render as waived-ok."

  - id: C0-PCF-F6
    severity: low
    step: 1
    finding: "Step 1's cap 'keep the file under 120 lines' is arithmetically incompatible with the declared row schema for 13 surfaces."
    evidence: "8 columns × 13 rows = 104 lines minimum in block YAML, plus the `surfaces:` key, plus the header comment which must document 5 disposition semantics AND the enumeration contract (≈10-15 lines), plus multi-line `writes:` lists for the init row (Step 5 assigns it permissions.yaml, project.yaml, integrations.yaml, CLAUDE.md, execution.yaml and the workspace files) and the setup row — realistically ≥130 lines."
    recommendation: "Raise the cap (e.g. ≤200 lines) or drop it; the constraint has no enforcement mechanism anyway and only creates a false AC risk."

  - id: C0-PCF-F7
    severity: low
    step: 2
    finding: "Step 2's `$AID_PLUGIN_PATH` precedent cite `test-aid-test-scheduler.bats:26` points at a file deleted from main."
    evidence: "`test -e plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-scheduler.bats` → missing; `git log --diff-filter=D -- '*test-aid-test-scheduler.bats'` → 2ce139c 'P078 Ring 1: remove the test-parallelism machinery' (already in HEAD). The mechanism itself is amply available: 95 bats files under scripts/tests/bats/ use AID_PLUGIN_PATH."
    recommendation: "Repoint the cite to a live suite (e.g. test-aid-init.bats or test-aid-run-gates.bats). No behavioural change."

  - id: C0-PCF-F8
    severity: low
    step: 14
    finding: "Step 14's new assertion 'every `final_turn: renderer:*` value names an existing script' will not resolve the value Step 1 seeds."
    evidence: "Step 1 seeds `final_turn: renderer:aid-test-audit-chat-summary.sh` — a bare basename; the file lives at `scripts/lib/aid-test-audit-chat-summary.sh` (verified present, exports `aid_test_audit_render_chat_summary()`, sourceable-only, no main — which is fine for Step 15's 'smoke only' use)."
    recommendation: "Fix the column grammar to repo-relative paths (`renderer:scripts/lib/aid-test-audit-chat-summary.sh`) in Step 1 so Step 14's existence assertion is mechanically satisfiable."

  - id: C0-PCF-F9
    severity: low
    step: 13
    finding: "Step 13's `_fsm_human_step` anchors are stale in both location and call-site count (expected — plan declares a rebase — recorded for the implementer)."
    evidence: "Helper is defined at aid-fsm.sh:1128-1132 (plan says ~819-840). Existing call sites are 3, at :2858, :2870, :5246 (plan lists 4, at :2430/:2442/:3935/:3945). No `current_step` interpolation was found at the cited lines."
    recommendation: "Re-derive the seam list at implementation time with `grep -n 'current_step\\|_fsm_human_step' scripts/aid-fsm.sh` rather than the plan's line numbers; keep the machine/human classification protocol as written."

confidence: high
